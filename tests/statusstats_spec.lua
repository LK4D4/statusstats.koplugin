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

local ui_manager_state = {
    shown = {},
    unscheduled = {},
    scheduled = {},
    broadcasted = {},
}

local function resetUIManagerState()
    ui_manager_state.shown = {}
    ui_manager_state.unscheduled = {}
    ui_manager_state.scheduled = {}
    ui_manager_state.broadcasted = {}
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
        show = function(_, widget)
            table.insert(ui_manager_state.shown, widget)
        end,
        unschedule = function(_, callback, context)
            table.insert(ui_manager_state.unscheduled, {
                callback = callback,
                context = context,
            })
        end,
        scheduleIn = function(_, delay, callback, context)
            table.insert(ui_manager_state.scheduled, {
                delay = delay,
                callback = callback,
                context = context,
            })
        end,
        broadcastEvent = function(_, event)
            table.insert(ui_manager_state.broadcasted, event)
        end,
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
    resetUIManagerState()

    local footer = {
        settings = {
            additional_content = false,
            all_at_once = true,
        },
        mode_list = {
            normal = "normal",
            additional_content = "additional_content",
        },
        mode_index = {
            normal = "normal",
            additional_content = "additional_content",
        },
        mode = "normal",
        add_calls = 0,
        remove_calls = 0,
        apply_calls = 0,
        refresh_calls = 0,
        update_calls = 0,
    }

    function footer:addAdditionalFooterContent(callback)
        self.add_calls = self.add_calls + 1
        self.additional_footer_content = self.additional_footer_content or {}
        table.insert(self.additional_footer_content, callback)
    end

    function footer:removeAdditionalFooterContent(callback)
        self.remove_calls = self.remove_calls + 1
        if self.additional_footer_content then
            for index, stored_callback in ipairs(self.additional_footer_content) do
                if stored_callback == callback then
                    table.remove(self.additional_footer_content, index)
                    break
                end
            end
        end
    end

    function footer:applyFooterMode(mode)
        self.apply_calls = self.apply_calls + 1
        self.mode = mode
    end

    function footer:refreshFooter(force)
        self.refresh_calls = self.refresh_calls + 1
        self.last_refresh_force = force
    end

    function footer:onUpdateFooter(refresh, force)
        self.update_calls = self.update_calls + 1
        self.last_update_args = { refresh, force }
    end

    local plugin = setmetatable({
        ui = {
            menu = {
                registerToMainMenu = function() end,
            },
            view = {
                footer = footer,
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

local time_refresh_plugin = newPlugin({
    show_value_in_footer = true,
    session = {
        time = true,
        pages = false,
    },
}, {
    session = {
        time = 125,
        pages = 0,
    },
    today = {
        time = 0,
        pages = 0,
    },
})

time_refresh_plugin:onReaderReady()

assertEquals(ui_manager_state.scheduled[#ui_manager_state.scheduled].delay, 55, "time-based footer refresh should align to the next minute boundary")

local pages_only_plugin = newPlugin({
    show_value_in_footer = true,
    session = {
        time = false,
        pages = true,
    },
}, {
    session = {
        time = 125,
        pages = 3,
    },
    today = {
        time = 0,
        pages = 0,
    },
})

pages_only_plugin:onReaderReady()

assertEquals(#ui_manager_state.scheduled, 0, "page-only status display should not start a periodic ticker")

local screensaver_plugin = newPlugin({
    show_value_in_footer = true,
}, {
    session = {
        time = 0,
        pages = 0,
    },
    today = {
        time = 0,
        pages = 0,
    },
})

screensaver_plugin:onOutOfScreenSaver()

assertEquals(ui_manager_state.broadcasted[#ui_manager_state.broadcasted].name, "RefreshAdditionalContent", "leaving the screensaver should refresh the footer content")

local startup_footer_plugin = newPlugin({
    show_value_in_footer = true,
}, {
    session = {
        time = 0,
        pages = 0,
    },
    today = {
        time = 0,
        pages = 0,
    },
})

startup_footer_plugin.ui.view.footer.settings.additional_content = false
startup_footer_plugin.ui.view.footer.settings.all_at_once = true
startup_footer_plugin.ui.view.footer.mode = "normal"

startup_footer_plugin:onReaderReady()

assertTrue(startup_footer_plugin.ui.view.footer.settings.additional_content, "reader ready should enable footer content mode when persisted")
assertEquals(startup_footer_plugin.ui.view.footer.mode, "additional_content", "reader ready should switch footer mode to additional content")
assertEquals(startup_footer_plugin.ui.view.footer.add_calls, 1, "reader ready should add footer content once")
assertEquals(startup_footer_plugin.ui.view.footer.refresh_calls, 1, "reader ready should refresh the footer after restoring visibility")

local restore_footer_plugin = newPlugin({
    show_value_in_footer = false,
}, {
    session = {
        time = 0,
        pages = 0,
    },
    today = {
        time = 0,
        pages = 0,
    },
})

restore_footer_plugin.ui.view.footer.settings.additional_content = false
restore_footer_plugin.ui.view.footer.settings.all_at_once = true
restore_footer_plugin.ui.view.footer.mode = "normal"

restore_footer_plugin:addAdditionalFooterContent()
assertTrue(restore_footer_plugin:ensureFooterModeShowsPluginContent(), "enabling footer stats should surface plugin content")
assertTrue(restore_footer_plugin.ui.view.footer.settings.additional_content, "enabling footer stats should flip additional content on")
assertEquals(restore_footer_plugin.ui.view.footer.mode, "additional_content", "enabling footer stats should switch footer mode")

restore_footer_plugin:removeAdditionalFooterContent()

assertTrue(not restore_footer_plugin.ui.view.footer.settings.additional_content, "disabling footer stats should restore additional content setting")
assertTrue(restore_footer_plugin.ui.view.footer.settings.all_at_once, "disabling footer stats should restore all-at-once setting")
assertEquals(restore_footer_plugin.ui.view.footer.mode, "normal", "disabling footer stats should restore the previous footer mode")
assertEquals(restore_footer_plugin.ui.view.footer.remove_calls, 1, "disabling footer stats should remove footer content once")

print("statusstats smoke tests passed")
