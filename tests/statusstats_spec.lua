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
                getCurrentBookStats = function()
                    return stats.session.time, stats.session.pages
                end,
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
    session = {
        time = true,
        pages = true,
    },
    today = {
        time = true,
        pages = true,
    },
    show_value_in_footer = true,
}, {
    session = {
        time = 120,
        pages = 3,
    },
    today = {
        time = 2880,
        pages = 11,
    },
})

assertEquals(
    plugin:getStatusText(false),
    "S 2m 3p | T 48m 11p",
    "footer text should render session and today stats with scope prefixes"
)

local session_only_plugin = newPlugin({
    session = {
        time = true,
        pages = false,
    }
}, {
    session = {
        time = 180,
        pages = 4,
    },
    today = {
        time = 0,
        pages = 0,
    },
})

assertEquals(
    session_only_plugin:getStatusText(false),
    "S 3m",
    "session-only output should omit disabled fields and sections"
)

local sub_minute_plugin = newPlugin({
    today = {
        time = true,
        pages = false,
    },
}, {
    today = {
        time = 59,
        pages = 2,
    },
    session = {
        time = 0,
        pages = 0,
    },
})

assertEquals(
    sub_minute_plugin:getStatusText(false),
    "T <1m",
    "sub-minute durations should not show seconds"
)

local default_settings_plugin = newPlugin({}, {
    session = {
        time = 0,
        pages = 0,
    },
    today = {
        time = 0,
        pages = 0,
    },
})

assertTrue(default_settings_plugin.settings.session.time == false, "session time should default to disabled")
assertTrue(default_settings_plugin.settings.session.pages == false, "session pages should default to disabled")
assertTrue(default_settings_plugin.settings.today.time == false, "today time should default to disabled")
assertTrue(default_settings_plugin.settings.today.pages == false, "today pages should default to disabled")

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
assertTrue(menu_text:find("Session", 1, true) ~= nil, "session menu should exist")
assertTrue(menu_text:find("Today", 1, true) ~= nil, "today menu should exist")
assertTrue(menu_text:find("Label style", 1, true) == nil, "label style menu should be removed")
assertTrue(menu_text:find("Book stats", 1, true) == nil, "book stats menu should be removed")

print("statusstats smoke tests passed")
