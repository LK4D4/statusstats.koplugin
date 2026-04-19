local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local DEFERRED_STATUS_REFRESH_DELAY = 0.001

local StatusStats = WidgetContainer:extend{
    name = "statusstats",
}

local DEFAULT_SETTINGS = {
    show_value_in_header = false,
    show_value_in_footer = false,
    session = {
        time = false,
        pages = false,
    },
    today = {
        time = false,
        pages = false,
    },
}

function StatusStats:normalizeSettings(settings)
    settings = settings or {}
    settings.show_value_in_header = settings.show_value_in_header or nil
    if settings.show_value_in_footer == nil then
        settings.show_value_in_footer = DEFAULT_SETTINGS.show_value_in_footer
    end

    if type(settings.session) ~= "table" then
        settings.session = {}
    end
    if settings.session.time == nil then
        settings.session.time = DEFAULT_SETTINGS.session.time
    end
    if settings.session.pages == nil then
        settings.session.pages = DEFAULT_SETTINGS.session.pages
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
    self.footer_state_before_plugin = nil

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
        self:ensureFooterModeShowsPluginContent()
    end
    self:startTicker()
    self:refreshStatusBars()
end

function StatusStats:onResume()
    self:scheduleDeferredStatusRefresh()
end

function StatusStats:onOutOfScreenSaver()
    self:scheduleDeferredStatusRefresh()
end

function StatusStats:onCloseWidget()
    self:removeAdditionalHeaderContent()
    self:removeAdditionalFooterContent()
    UIManager:unschedule(self.tickStatusBars, self)
    UIManager:unschedule(self.performDeferredStatusRefresh, self)
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

function StatusStats:getNowTimestamp()
    return os.time()
end

function StatusStats:getBaseStatisticsPair(statistics, method_name)
    if not (statistics and statistics[method_name]) then
        return {
            time = 0,
            pages = 0,
        }
    end

    local ok, duration, pages = pcall(statistics[method_name], statistics)
    if not ok then
        return {
            time = 0,
            pages = 0,
        }
    end

    return {
        time = tonumber(duration) or 0,
        pages = tonumber(pages) or 0,
    }
end

function StatusStats:getLiveTupleDurationSince(statistics, page, data_list, tuple_index, boundary_time)
    local tuple = data_list and data_list[tuple_index]
    if type(tuple) ~= "table" then
        return 0
    end

    local start_time = tonumber(tuple[1])
    local stored_duration = tonumber(tuple[2]) or 0
    if not start_time then
        return 0
    end

    local effective_duration = math.max(stored_duration, 0)
    local is_active_tuple = statistics.curr_page == page
        and tuple_index == #data_list
        and not statistics._reading_paused_ts

    if is_active_tuple then
        local settings = statistics.settings or {}
        local min_sec = tonumber(settings.min_sec) or 0
        local max_sec = tonumber(settings.max_sec) or math.huge
        local elapsed = math.max(self:getNowTimestamp() - start_time, 0)

        if elapsed >= min_sec then
            effective_duration = math.max(effective_duration, math.min(elapsed, max_sec))
        end
    end

    if effective_duration <= 0 then
        return 0
    end

    boundary_time = tonumber(boundary_time) or 0
    if start_time >= boundary_time then
        return effective_duration
    end

    local end_time = start_time + effective_duration
    if end_time <= boundary_time then
        return 0
    end

    return end_time - boundary_time
end

function StatusStats:getLiveStatisticsPair(statistics, boundary_time)
    if not (statistics and type(statistics.page_stat) == "table") then
        return {
            time = 0,
            pages = 0,
        }
    end

    local live_duration = 0
    local live_pages = 0

    for page, data_list in pairs(statistics.page_stat) do
        if type(data_list) == "table" then
            local page_duration = 0

            for tuple_index = 1, #data_list do
                page_duration = page_duration
                    + self:getLiveTupleDurationSince(statistics, page, data_list, tuple_index, boundary_time)
            end

            if page_duration > 0 then
                live_duration = live_duration + page_duration
                live_pages = live_pages + 1
            end
        end
    end

    return {
        time = live_duration,
        pages = live_pages,
    }
end

function StatusStats:getStatisticsPair(method_name, boundary_time)
    local statistics = self:getStatisticsPlugin()
    if not statistics then
        return nil
    end

    local persisted = self:getBaseStatisticsPair(statistics, method_name)
    local live = self:getLiveStatisticsPair(statistics, boundary_time)

    return {
        time = persisted.time + live.time,
        pages = persisted.pages + live.pages,
    }
end

function StatusStats:getTodayStats()
    local now_stamp = self:getNowTimestamp()
    local now_t = os.date("*t", now_stamp)
    local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
    local start_today_time = now_stamp - from_begin_day
    return self:getStatisticsPair("getTodayBookStats", start_today_time)
end

function StatusStats:getSessionStats()
    local statistics = self:getStatisticsPlugin()
    local boundary_time = statistics and statistics.start_current_period or self:getNowTimestamp()
    return self:getStatisticsPair("getCurrentBookStats", boundary_time)
end

function StatusStats:formatDuration(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then
        return "0m"
    end
    if seconds < 60 then
        return "<1m"
    end

    local total_minutes = math.floor(seconds / 60)
    local hours = math.floor(total_minutes / 60)
    local minutes = total_minutes % 60

    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes)
    end

    return string.format("%dm", total_minutes)
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

function StatusStats:getFooterModeName()
    local footer = self.ui and self.ui.view and self.ui.view.footer
    if not (footer and footer.mode and footer.mode_index) then
        return "n/a"
    end
    return footer.mode_index[footer.mode] or tostring(footer.mode)
end

function StatusStats:ensureFooterModeShowsPluginContent()
    local footer = self.ui and self.ui.view and self.ui.view.footer
    if not (footer and footer.settings) then
        return false
    end

    if not self.footer_state_before_plugin then
        self.footer_state_before_plugin = {
            additional_content = footer.settings.additional_content,
            all_at_once = footer.settings.all_at_once,
            mode = footer.mode,
        }
    end

    footer.settings.additional_content = true
    if footer.settings.all_at_once == nil then
        footer.settings.all_at_once = false
    end

    if footer.mode_list and footer.mode_list.additional_content then
        footer.mode = footer.mode_list.additional_content
    end

    if footer.applyFooterMode then
        footer:applyFooterMode(footer.mode)
    end

    if footer.refreshFooter then
        footer:refreshFooter(true)
    elseif footer.onUpdateFooter then
        footer:onUpdateFooter(true, true)
    end

    return true
end

function StatusStats:restoreFooterModeIfNeeded()
    local footer = self.ui and self.ui.view and self.ui.view.footer
    local state = self.footer_state_before_plugin
    if not (footer and footer.settings and state) then
        return false
    end

    footer.settings.additional_content = state.additional_content
    footer.settings.all_at_once = state.all_at_once
    footer.mode = state.mode

    if footer.applyFooterMode then
        footer:applyFooterMode(footer.mode)
    end

    if footer.refreshFooter then
        footer:refreshFooter(true)
    elseif footer.onUpdateFooter then
        footer:onUpdateFooter(true, true)
    end

    self.footer_state_before_plugin = nil
    return true
end

function StatusStats:showDebugInfo()
    local ok, result = pcall(function()
        local footer = self.ui and self.ui.view and self.ui.view.footer
        local statistics = self:getStatisticsPlugin()
        local additional_count = footer and footer.additional_footer_content and #footer.additional_footer_content or 0
        local sample_ok, sample_text = pcall(self.getStatusText, self, false)
        local session_ok, session = pcall(self.getSessionStats, self)
        local today_ok, today = pcall(self.getTodayStats, self)

        local lines = {
            "footer_content_added: " .. tostring(self.footer_content_added),
            "header_content_added: " .. tostring(self.header_content_added),
            "footer mode: " .. tostring(self:getFooterModeName()),
            "footer settings.additional_content: " .. tostring(footer and footer.settings and footer.settings.additional_content),
            "footer settings.all_at_once: " .. tostring(footer and footer.settings and footer.settings.all_at_once),
            "footer additional count: " .. tostring(additional_count),
            "statistics plugin: " .. tostring(statistics ~= nil),
            "session stats ok: " .. tostring(session_ok),
            "session stats: " .. tostring(session_ok and session and (session.time .. "s/" .. session.pages .. "p") or session),
            "today stats ok: " .. tostring(today_ok),
            "today stats: " .. tostring(today_ok and today and (today.time .. "s/" .. today.pages .. "p") or today),
            "sample footer text ok: " .. tostring(sample_ok),
            "sample footer text: " .. tostring(sample_ok and sample_text or sample_text),
        }

        return table.concat(lines, "\n")
    end)

    UIManager:show(InfoMessage:new{
        text = ok and result or ("debug info failed: " .. tostring(result)),
    })
end

function StatusStats:getSectionText(prefix, stats, enabled)
    if not enabled.time and not enabled.pages then
        return nil
    end

    local parts = { prefix }
    if enabled.time then
        local time_text = stats and self:formatDuration(stats.time) or _("N/A")
        table.insert(parts, time_text)
    end
    if enabled.pages then
        local pages_text = stats and string.format("%sp", tostring(stats.pages)) or _("N/A")
        table.insert(parts, pages_text)
    end

    return table.concat(parts, " ")
end

function StatusStats:getStatusText(is_header)
    local sections = {}

    local session = self:getSectionText("S", self:getSessionStats(), self.settings.session)
    if session then
        table.insert(sections, session)
    end

    local today = self:getSectionText("T", self:getTodayStats(), self.settings.today)
    if today then
        table.insert(sections, today)
    end

    if #sections == 0 then
        return nil
    end

    return table.concat(sections, self:getSeparator())
end

function StatusStats:onPageUpdate()
    self:scheduleDeferredStatusRefresh()
end

function StatusStats:onPosUpdate()
    self:scheduleDeferredStatusRefresh()
end

function StatusStats:onSuspend()
    self:refreshStatusBars()
end

function StatusStats:performDeferredStatusRefresh()
    self:refreshStatusBars()
    self:startTicker()
end

function StatusStats:scheduleDeferredStatusRefresh(delay)
    UIManager:unschedule(self.performDeferredStatusRefresh, self)
    UIManager:scheduleIn(delay or DEFERRED_STATUS_REFRESH_DELAY, self.performDeferredStatusRefresh, self)
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

function StatusStats:getNextDurationRefreshDelay(seconds)
    seconds = tonumber(seconds) or 0
    if seconds <= 0 then
        return 1
    end
    if seconds < 60 then
        return 60 - seconds
    end

    local remainder = seconds % 60
    if remainder == 0 then
        return 60
    end
    return 60 - remainder
end

function StatusStats:getNextStatusRefreshDelay()
    local delays = {}

    if self.settings.session.time then
        local session = self:getSessionStats()
        if session then
            table.insert(delays, self:getNextDurationRefreshDelay(session.time))
        end
    end

    if self.settings.today.time then
        local today = self:getTodayStats()
        if today then
            table.insert(delays, self:getNextDurationRefreshDelay(today.time))
        end
    end

    if #delays == 0 then
        if self.settings.session.time or self.settings.today.time then
            return 60
        end
        return nil
    end

    local next_delay = delays[1]
    for index = 2, #delays do
        next_delay = math.min(next_delay, delays[index])
    end
    return next_delay
end

function StatusStats:startTicker()
    UIManager:unschedule(self.tickStatusBars, self)
    if self.settings.show_value_in_header or self.settings.show_value_in_footer then
        local next_delay = self:getNextStatusRefreshDelay()
        if next_delay then
            UIManager:scheduleIn(next_delay, self.tickStatusBars, self)
        end
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
        self:restoreFooterModeIfNeeded()
        UIManager:broadcastEvent(Event:new("UpdateFooter", true))
    end
end

function StatusStats:addToMainMenu(menu_items)
    menu_items.status_stats = {
        text = _("Status stats"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Show debug info"),
                keep_menu_open = true,
                callback = function()
                    self:showDebugInfo()
                end,
            },
            {
                text = _("Session"),
                sub_item_table = {
                    {
                        text = _("Time spent reading this session"),
                        checked_func = function()
                            return self.settings.session.time
                        end,
                        callback = function()
                            self:toggleNestedSetting("session", "time")
                        end,
                    },
                    {
                        text = _("Pages read this session"),
                        checked_func = function()
                            return self.settings.session.pages
                        end,
                        callback = function()
                            self:toggleNestedSetting("session", "pages")
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
                            self:ensureFooterModeShowsPluginContent()
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
