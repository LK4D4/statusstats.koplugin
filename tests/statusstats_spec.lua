package.path = "./?.lua;./?/init.lua;" .. package.path

local function assertEquals(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s\nexpected: %s\nactual: %s", message or "assertEquals failed", tostring(expected), tostring(actual)))
    end
end

local function assertTrue(value, message)
    if not value then
        error(message or "assertTrue failed")
    end
end

package.preload["ui/event"] = function()
    return {
        new = function(_, name)
            return { name = name }
        end,
    }
end

package.preload["ui/widget/infomessage"] = function()
    return {
        new = function(_, opts)
            return opts
        end,
    }
end

package.preload["ui/uimanager"] = function()
    return {
        show = function() end,
        unschedule = function() end,
        scheduleIn = function() end,
        broadcastEvent = function() end,
    }
end

package.preload["ui/widget/container/widgetcontainer"] = function()
    local WidgetContainer = {}

    function WidgetContainer:extend(definition)
        definition = definition or {}
        definition.__index = definition
        return setmetatable(definition, { __index = self })
    end

    return WidgetContainer
end

package.preload["datetime"] = function()
    return {
        secondsToClockDuration = function(_, seconds)
            return string.format("%ss", seconds)
        end,
    }
end

package.preload["gettext"] = function()
    return function(text)
        return text
    end
end

local saved_settings
_G.G_reader_settings = {
    readSetting = function(_, key, default)
        if key == "statusstats" then
            return saved_settings or default
        end
        if key == "duration_format" then
            return "classic"
        end
        return default
    end,
    saveSetting = function(_, key, value)
        if key == "statusstats" then
            saved_settings = value
        end
    end,
}

local StatusStats = dofile("main.lua")

local function newPlugin(settings, stats)
    saved_settings = settings

    local plugin = setmetatable({
        ui = {
            menu = {
                registerToMainMenu = function() end,
            },
            view = {
                footer = {
                    genSeparator = function()
                        return " | "
                    end,
                },
            },
            statistics = {
                getTodayBookStats = function()
                    return stats.today.time, stats.today.pages
                end,
            },
        },
    }, { __index = StatusStats })

    plugin:init()
    return plugin
end

local plugin = newPlugin({
    today = {
        time = true,
        pages = true,
    },
    show_value_in_footer = true,
}, {
    today = {
        time = 120,
        pages = 3,
    },
})

assertEquals(
    plugin:getStatusText(false),
    "⌛ 120s ▤ 3p",
    "compact footer text should render today stats with symbols"
)

local long_label_plugin = newPlugin({
    today = {
        time = true,
        pages = false,
    },
    label_mode = "long",
}, {
    today = {
        time = 180,
        pages = 4,
    },
})

assertEquals(
    long_label_plugin:getStatusText(false),
    "Today: 180s",
    "long label mode should use a text label for today stats"
)

local migrated_plugin = newPlugin({
    book = {
        time = true,
        pages = true,
    },
}, {
    today = {
        time = 60,
        pages = 2,
    },
})

assertTrue(migrated_plugin.settings.today.time == true, "legacy book time should migrate to today settings")
assertTrue(migrated_plugin.settings.today.pages == true, "legacy book pages should migrate to today settings")

local menu_items = {}
plugin:addToMainMenu(menu_items)
assertTrue(menu_items.status_stats ~= nil, "status stats menu should exist")

local menu_entry_names = {}
for _, item in ipairs(menu_items.status_stats.sub_item_table) do
    table.insert(menu_entry_names, item.text)
end

local menu_text = table.concat(menu_entry_names, "\n")
assertTrue(not menu_text:find("Show plugin content in footer now", 1, true), "temporary footer debug action should be removed")
assertTrue(menu_text:find("Show debug info", 1, true) ~= nil, "debug info action should still be available")
assertTrue(menu_text:find("Label style", 1, true) ~= nil, "label style menu should exist")
assertTrue(menu_text:find("Today", 1, true) ~= nil, "today menu should exist")
assertTrue(menu_text:find("Book stats", 1, true) == nil, "book stats menu should be removed")

print("statusstats smoke tests passed")
