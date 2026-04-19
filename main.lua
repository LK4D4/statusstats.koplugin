local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local _ = require("gettext")

local StatusStats = WidgetContainer:extend{
    name = "statusstats",
}

local DEFAULT_SETTINGS = {
    show_value_in_header = false,
    show_value_in_footer = true,
    current_session = {
        time = true,
        pages = true,
    },
    today = {
        time = true,
        pages = true,
    },
}

function StatusStats:normalizeSettings(settings)
    settings = settings or {}
    settings.show_value_in_header = settings.show_value_in_header or nil
    if settings.show_value_in_footer == nil then
        settings.show_value_in_footer = DEFAULT_SETTINGS.show_value_in_footer
    end

    if type(settings.current_session) ~= "table" then
        settings.current_session = {}
    end
    if settings.current_session.time == nil then
        settings.current_session.time = DEFAULT_SETTINGS.current_session.time
    end
    if settings.current_session.pages == nil then
        settings.current_session.pages = DEFAULT_SETTINGS.current_session.pages
    end

    if type(settings.today) ~= "table" then
        settings.today = {}
    end
    if settings.today.time == nil then
        settings.today.time = DEFAULT_SETTINGS.today.time
    end
    if settings.today.pages == nil then
        settings.today.pages = DEFAULT_SETTINGS.today.pages
    end

    return settings
end

function StatusStats:init()
    self.settings = self:normalizeSettings(G_reader_settings:readSetting("statusstats", DEFAULT_SETTINGS))
    self.header_content_added = false
    self.footer_content_added = false

    self.additional_header_content_func = function()
        local ok, text = pcall(self.getStatusText, self, true)
        if ok then
            return text
        end
        return nil
    end

    self.additional_footer_content_func = function()
        local ok, text = pcall(self.getStatusText, self, false)
        if ok then
            return text
        end
        return nil
    end

    self.ui.menu:registerToMainMenu(self)
end

function StatusStats:onReaderReady()
    if self.settings.show_value_in_header then
        self:addAdditionalHeaderContent()
    end
    if self.settings.show_value_in_footer then
        self:addAdditionalFooterContent()
    end
    self:startTicker()
    self:refreshStatusBars()
end

function StatusStats:onResume()
    self:refreshStatusBars()
end

function StatusStats:onCloseWidget()
    self:removeAdditionalHeaderContent()
    self:removeAdditionalFooterContent()
    UIManager:unschedule(self.tickStatusBars, self)
end

function StatusStats:persistSettings()
    G_reader_settings:saveSetting("statusstats", self.settings)
end

function StatusStats:getStatisticsPlugin()
    if self.ui and self.ui.statistics then
        return self.ui.statistics
    end
    return nil
end

function StatusStats:getStatisticsPair(method_name)
    local statistics = self:getStatisticsPlugin()
    if not (statistics and statistics[method_name]) then
        return nil
    end

    local ok, duration, pages = pcall(statistics[method_name], statistics)
    if not ok then
        return nil
    end

    return {
        time = tonumber(duration) or 0,
        pages = tonumber(pages) or 0,
    }
end

function StatusStats:getCurrentSessionStats()
    return self:getStatisticsPair("getCurrentBookStats")
end

function StatusStats:getTodayStats()
    return self:getStatisticsPair("getTodayBookStats")
end

function StatusStats:formatDuration(seconds)
    local user_duration_format = G_reader_settings:readSetting("duration_format", "classic")
    return datetime.secondsToClockDuration(user_duration_format, seconds, false)
end

function StatusStats:getSeparator()
    local footer = self.ui and self.ui.view and self.ui.view.footer
    if footer and footer.genSeparator then
        local ok, separator = pcall(footer.genSeparator, footer)
        if ok and type(separator) == "string" and separator ~= "" then
            return separator
        end
    end
    return " | "
end

function StatusStats:getSectionText(label, stats, enabled)
    if not enabled.time and not enabled.pages then
        return nil
    end

    local parts = {}
    if enabled.time then
        local time_value = stats and self:formatDuration(stats.time) or _("N/A")
        table.insert(parts, string.format("%s %s", label, time_value))
    end
    if enabled.pages then
        local pages_value = stats and tostring(stats.pages) or _("N/A")
        table.insert(parts, string.format("%s %sp", label, pages_value))
    end

    if #parts == 0 then
        return nil
    end

    return table.concat(parts, self:getSeparator())
end

function StatusStats:getStatusText(_)
    local sections = {}

    local current_session = self:getSectionText(_("CS"), self:getCurrentSessionStats(), self.settings.current_session)
    if current_session then
        table.insert(sections, current_session)
    end

    local today = self:getSectionText(_("TD"), self:getTodayStats(), self.settings.today)
    if today then
        table.insert(sections, today)
    end

    if #sections == 0 then
        return nil
    end

    return table.concat(sections, self:getSeparator())
end

function StatusStats:onPageUpdate()
    self:refreshStatusBars()
end

function StatusStats:onPosUpdate()
    self:refreshStatusBars()
end

function StatusStats:onSuspend()
    self:refreshStatusBars()
end

function StatusStats:refreshStatusBars()
    if self.settings.show_value_in_header then
        UIManager:broadcastEvent(Event:new("UpdateHeader"))
    end
    if self.settings.show_value_in_footer then
        UIManager:broadcastEvent(Event:new("RefreshAdditionalContent"))
    end
end

function StatusStats:tickStatusBars()
    self:refreshStatusBars()
    self:startTicker()
end

function StatusStats:startTicker()
    UIManager:unschedule(self.tickStatusBars, self)
    if self.settings.show_value_in_header or self.settings.show_value_in_footer then
        UIManager:scheduleIn(60, self.tickStatusBars, self)
    end
end

function StatusStats:toggleNestedSetting(section, key)
    self.settings[section][key] = not self.settings[section][key] or nil
    self:persistSettings()
    self:startTicker()
    self:refreshStatusBars()
end

function StatusStats:toggleDisplaySetting(key, callback)
    self.settings[key] = not self.settings[key] or nil
    if callback then
        callback(self.settings[key])
    end
    self:persistSettings()
    self:startTicker()
    self:refreshStatusBars()
end

function StatusStats:addAdditionalHeaderContent()
    if self.ui.crelistener and not self.header_content_added then
        self.ui.crelistener:addAdditionalHeaderContent(self.additional_header_content_func)
        self.header_content_added = true
    end
end

function StatusStats:removeAdditionalHeaderContent()
    if self.ui.crelistener and self.header_content_added then
        self.ui.crelistener:removeAdditionalHeaderContent(self.additional_header_content_func)
        self.header_content_added = false
        UIManager:broadcastEvent(Event:new("UpdateHeader"))
    end
end

function StatusStats:addAdditionalFooterContent()
    if self.ui.view and self.ui.view.footer and not self.footer_content_added then
        self.ui.view.footer:addAdditionalFooterContent(self.additional_footer_content_func)
        self.footer_content_added = true
    end
end

function StatusStats:removeAdditionalFooterContent()
    if self.ui.view and self.ui.view.footer and self.footer_content_added then
        self.ui.view.footer:removeAdditionalFooterContent(self.additional_footer_content_func)
        self.footer_content_added = false
        UIManager:broadcastEvent(Event:new("UpdateFooter", true))
    end
end

function StatusStats:addToMainMenu(menu_items)
    menu_items.status_stats = {
        text = _("Status stats"),
        sorting_hint = "more_tools",
        sub_item_table = {
            {
                text = _("Current session"),
                sub_item_table = {
                    {
                        text = _("Time spent reading this session"),
                        checked_func = function()
                            return self.settings.current_session.time
                        end,
                        callback = function()
                            self:toggleNestedSetting("current_session", "time")
                        end,
                    },
                    {
                        text = _("Pages read this session"),
                        checked_func = function()
                            return self.settings.current_session.pages
                        end,
                        callback = function()
                            self:toggleNestedSetting("current_session", "pages")
                        end,
                    },
                },
            },
            {
                text = _("Today"),
                sub_item_table = {
                    {
                        text = _("Time spent reading today"),
                        checked_func = function()
                            return self.settings.today.time
                        end,
                        callback = function()
                            self:toggleNestedSetting("today", "time")
                        end,
                    },
                    {
                        text = _("Pages read today"),
                        checked_func = function()
                            return self.settings.today.pages
                        end,
                        callback = function()
                            self:toggleNestedSetting("today", "pages")
                        end,
                    },
                },
            },
            {
                text = _("Show in alt status bar"),
                checked_func = function()
                    return self.settings.show_value_in_header
                end,
                callback = function()
                    self:toggleDisplaySetting("show_value_in_header", function(enabled)
                        if enabled then
                            self:addAdditionalHeaderContent()
                        else
                            self:removeAdditionalHeaderContent()
                        end
                    end)
                end,
            },
            {
                text = _("Show in status bar"),
                checked_func = function()
                    return self.settings.show_value_in_footer
                end,
                callback = function()
                    self:toggleDisplaySetting("show_value_in_footer", function(enabled)
                        if enabled then
                            self:addAdditionalFooterContent()
                        else
                            self:removeAdditionalFooterContent()
                        end
                    end)
                end,
            },
        },
    }
end

return StatusStats
