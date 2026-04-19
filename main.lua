local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local datetime = require("datetime")
local _ = require("gettext")

local StatusStats = WidgetContainer:extend{
    name = "statusstats",
}

local DEFAULT_SETTINGS = {
    show_value_in_header = false,
    show_value_in_footer = false,
    label_mode = "compact",
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
    if settings.label_mode ~= "long" then
        settings.label_mode = DEFAULT_SETTINGS.label_mode
    end

    if type(settings.today) ~= "table" then
        if type(settings.book) == "table" then
            settings.today = {
                time = settings.book.time,
                pages = settings.book.pages,
            }
        elseif type(settings.current_session) == "table" then
            settings.today = {
                time = settings.current_session.time,
                pages = settings.current_session.pages,
            }
        else
            settings.today = {}
        end
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

function StatusStats:showDebugInfo()
    local ok, result = pcall(function()
        local footer = self.ui and self.ui.view and self.ui.view.footer
        local statistics = self:getStatisticsPlugin()
        local additional_count = footer and footer.additional_footer_content and #footer.additional_footer_content or 0
        local sample_ok, sample_text = pcall(self.getStatusText, self, false)
        local today_ok, today = pcall(self.getTodayStats, self)

        local lines = {
            "footer_content_added: " .. tostring(self.footer_content_added),
            "header_content_added: " .. tostring(self.header_content_added),
            "footer mode: " .. tostring(self:getFooterModeName()),
            "footer settings.additional_content: " .. tostring(footer and footer.settings and footer.settings.additional_content),
            "footer settings.all_at_once: " .. tostring(footer and footer.settings and footer.settings.all_at_once),
            "footer additional count: " .. tostring(additional_count),
            "statistics plugin: " .. tostring(statistics ~= nil),
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

function StatusStats:getSectionText(label, stats, enabled)
    if not enabled.time and not enabled.pages then
        return nil
    end

    local parts = {}
    if enabled.time then
        local time_text = stats and self:formatDuration(stats.time) or _("N/A")
        if self.settings.label_mode == "long" then
            table.insert(parts, time_text)
        else
            table.insert(parts, string.format("⌛ %s", time_text))
        end
    end
    if enabled.pages then
        local pages_text = string.format("%sp", stats and tostring(stats.pages) or _("N/A"))
        if self.settings.label_mode == "long" then
            table.insert(parts, pages_text)
        else
            table.insert(parts, string.format("▤ %s", pages_text))
        end
    end

    if #parts == 0 then
        return nil
    end

    if self.settings.label_mode ~= "long" then
        return table.concat(parts, " ")
    end

    return string.format("%s: %s", label, table.concat(parts, ", "))
end

function StatusStats:getSectionLabel(section_name)
    local labels = {
        long = {
            today = _("Today"),
        },
    }

    local mode = labels[self.settings.label_mode] and self.settings.label_mode or DEFAULT_SETTINGS.label_mode
    return labels[mode] and labels[mode][section_name] or nil
end

function StatusStats:getStatusText(is_header)
    local sections = {}

    local today = self:getSectionText(self:getSectionLabel("today"), self:getTodayStats(), self.settings.today)
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

function StatusStats:setLabelMode(mode)
    self.settings.label_mode = mode == "long" and "long" or DEFAULT_SETTINGS.label_mode
    self:persistSettings()
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
                text = _("Label style"),
                sub_item_table = {
                    {
                        text = _("Compact"),
                        checked_func = function()
                            return self.settings.label_mode ~= "long"
                        end,
                        callback = function()
                            self:setLabelMode("compact")
                        end,
                    },
                    {
                        text = _("Long"),
                        checked_func = function()
                            return self.settings.label_mode == "long"
                        end,
                        callback = function()
                            self:setLabelMode("long")
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
