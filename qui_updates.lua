--[[
QuickUI - Update Module

Check for updates from GitHub/Gitee and download/install new versions.
Copied from cloudlibrary.koplugin/update.lua and adapted for QuickUI.

Author: gytwo
]]

local logger = require("logger")
local UIManager = require("ui/uimanager")
local Notification = require("ui/widget/notification")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")
local Device = require("device")
local Screen = Device.screen

local Updates = {}

local plugin = nil

local REPO_OWNER = "gytwo"
local REPO_NAME = "quickui.koplugin"
local MANUAL_ZIP_NAME = "quickui.koplugin.zip"

local is_android = Device:isAndroid()

-- Update sources
local SOURCES = {
    github_latest = {
        name = "GitHub (Latest)",
        api_url = "https://api.github.com/repos/%s/%s/releases/latest",
        list_url = "https://api.github.com/repos/%s/%s/releases",
        type = "github",
        prerelease = false,
    },
    github_prerelease = {
        name = "GitHub (Pre-release)",
        api_url = "https://api.github.com/repos/%s/%s/releases",
        list_url = "https://api.github.com/repos/%s/%s/releases",
        type = "github",
        prerelease = true,
    },
    gitee_latest = {
        name = "Gitee (Latest)",
        api_url = "https://gitee.com/api/v5/repos/%s/%s/releases/latest",
        list_url = "https://gitee.com/api/v5/repos/%s/%s/releases",
        type = "gitee",
        prerelease = false,
    },
}

-- Get plugin directory
local Utils = require("qui_utils")
local _plugin_dir = Utils.getPluginDir()

-- Get current version from _meta.lua
local function getCurrentVersion()
    local meta_path = _plugin_dir .. "_meta.lua"
    local f = io.open(meta_path, "r")
    if not f then
        return "1.0.0"
    end
    local content = f:read("*all")
    f:close()
    local version = content:match('version%s*=%s*"([^"]+)"')
    if not version then
        version = content:match("version%s*=%s*'([^']+)'")
    end
    return version or "1.0.0"
end

-- Save/load update source
local function saveSource(key)
    G_reader_settings:saveSetting("quickui_update_source", key)
end

local function getSourceKey()
    local saved = G_reader_settings:readSetting("quickui_update_source")
    if saved == "github_prerelease" then
        return "github_prerelease"
    elseif saved == "gitee_latest" then
        return "gitee_latest"
    else
        return "github_latest"
    end
end

local function getSourceByKey(key)
    if key == "github_prerelease" then
        return SOURCES.github_prerelease
    elseif key == "gitee_latest" then
        return SOURCES.gitee_latest
    else
        return SOURCES.github_latest
    end
end

-- HTTP request
local function requestUrl(url, timeout)
    timeout = timeout or 10
    logger.info("QuickUI Updates: Requesting " .. url)

    local http = require("socket.http")
    local ltn12 = require("ltn12")

    local response = {}
    local ok, err = pcall(function()
        return http.request{
            url = url,
            sink = ltn12.sink.table(response),
            headers = {
                ["User-Agent"] = "KOReader-QuickUI",
                ["Accept"] = "application/json",
            },
            timeout = timeout,
        }
    end)

    if not ok then
        logger.warn("QuickUI Updates: HTTP request failed: " .. tostring(err))
        return nil
    end
    if not response or #response == 0 then
        logger.warn("QuickUI Updates: Empty response")
        return nil
    end

    local response_str = table.concat(response)
    local json = require("json")
    local success, data = pcall(json.decode, response_str)
    if not success or not data then
        logger.warn("QuickUI Updates: JSON parse failed")
        return nil
    end
    return data
end

-- Parse release data
local function parseReleaseData(data, source)
    local tag_name = data.tag_name or data.name
    logger.info("QuickUI Updates: Latest version: " .. tag_name .. " (source: " .. source.name .. ")")

    local zip_url = nil
    if data.assets then
        for i, asset in ipairs(data.assets) do
            if asset.name == MANUAL_ZIP_NAME then
                zip_url = asset.browser_download_url
                logger.info("QuickUI Updates: Using manually uploaded ZIP")
                break
            end
        end
    end
    if not zip_url and data.zipball_url then
        zip_url = data.zipball_url
        logger.info("QuickUI Updates: Using auto-generated source ZIP")
    end

    return tag_name, zip_url, source.name, data.body
end

-- Get latest from GitHub
local function getLatestFromGithub(source)
    local url = string.format(source.api_url, REPO_OWNER, REPO_NAME)

    if source.prerelease then
        local data = requestUrl(url, 15)
        if not data or #data == 0 then
            return nil, nil, nil, _("Failed to get version information")
        end

        local latest_prerelease = nil
        for i, release in ipairs(data) do
            if release.prerelease == true then
                if not latest_prerelease then
                    latest_prerelease = release
                else
                    local current_time = os.time()
                    local release_time = os.time({
                        year = tonumber(release.created_at:sub(1,4)),
                        month = tonumber(release.created_at:sub(6,7)),
                        day = tonumber(release.created_at:sub(9,10)),
                        hour = tonumber(release.created_at:sub(12,13)) or 0,
                        min = tonumber(release.created_at:sub(15,16)) or 0,
                        sec = tonumber(release.created_at:sub(18,19)) or 0,
                    })
                    local latest_time = os.time({
                        year = tonumber(latest_prerelease.created_at:sub(1,4)),
                        month = tonumber(latest_prerelease.created_at:sub(6,7)),
                        day = tonumber(latest_prerelease.created_at:sub(9,10)),
                        hour = tonumber(latest_prerelease.created_at:sub(12,13)) or 0,
                        min = tonumber(latest_prerelease.created_at:sub(15,16)) or 0,
                        sec = tonumber(latest_prerelease.created_at:sub(18,19)) or 0,
                    })
                    if release_time > latest_time then
                        latest_prerelease = release
                    end
                end
            end
        end

        if not latest_prerelease then
            return nil, nil, nil, _("No pre-release found")
        end

        return parseReleaseData(latest_prerelease, source)
    else
        local data = requestUrl(url, 15)
        if not data or not data.tag_name then
            return nil, nil, nil, _("Failed to get version information")
        end
        return parseReleaseData(data, source)
    end
end

-- Get latest from Gitee
local function getLatestFromGitee(source)
    local url = string.format(source.api_url, REPO_OWNER, REPO_NAME)
    local data = requestUrl(url, 15)

    if not data or not data.tag_name then
        return nil, nil, nil, _("Failed to get version information")
    end

    return parseReleaseData(data, source)
end

-- Get latest version from source
local function getLatestVersionFromSource(source)
    if source.type == "github" then
        return getLatestFromGithub(source)
    else
        return getLatestFromGitee(source)
    end
end

-- Get all versions for downgrade
local function getAllVersionsFromSource(source)
    local all_versions = {}
    local url = string.format(source.list_url, REPO_OWNER, REPO_NAME)

    if source.type == "github" and source.prerelease then
        local data = requestUrl(url .. "?per_page=100", 15)
        if not data or #data == 0 then
            return {}
        end

        for i, release in ipairs(data) do
            if release.prerelease == true then
                local tag_name = release.tag_name or release.name
                if tag_name then
                    local zip_url = nil
                    if release.assets then
                        for i, asset in ipairs(release.assets) do
                            if asset.name == MANUAL_ZIP_NAME then
                                zip_url = asset.browser_download_url
                                break
                            end
                        end
                    end
                    table.insert(all_versions, {
                        tag = tag_name,
                        url = zip_url,
                        body = release.body,
                        source = source.name,
                    })
                end
            end
        end
    elseif source.type == "github" then
        local data = requestUrl(url .. "?per_page=100", 15)
        if not data or #data == 0 then
            return {}
        end

        for i, release in ipairs(data) do
            if release.prerelease ~= true then
                local tag_name = release.tag_name or release.name
                if tag_name then
                    local zip_url = nil
                    if release.assets then
                        for i, asset in ipairs(release.assets) do
                            if asset.name == MANUAL_ZIP_NAME then
                                zip_url = asset.browser_download_url
                                break
                            end
                        end
                    end
                    table.insert(all_versions, {
                        tag = tag_name,
                        url = zip_url,
                        body = release.body,
                        source = source.name,
                    })
                end
            end
        end
    else
        local page = 1
        while true do
            local paged_url = url .. "?page=" .. tostring(page) .. "&per_page=100"
            local data = requestUrl(paged_url, 15)

            if not data or #data == 0 then
                break
            end

            for i, release in ipairs(data) do
                local tag_name = release.tag_name or release.name
                if tag_name then
                    local zip_url = nil
                    if release.assets then
                        for i, asset in ipairs(release.assets) do
                            if asset.name == MANUAL_ZIP_NAME then
                                zip_url = asset.browser_download_url
                                break
                            end
                        end
                    end
                    table.insert(all_versions, {
                        tag = tag_name,
                        url = zip_url,
                        body = release.body,
                        source = source.name,
                    })
                end
            end

            if #data < 100 then
                break
            end
            page = page + 1
        end
    end

    return all_versions
end

-- Compare versions
local function isNewerVersion(current, latest)
    if current == latest then return false end

    local cur = current:gsub("^v", "")
    local lat = latest:gsub("^v", "")

    local cur_parts = {}
    for part in cur:gmatch("[^.]+") do
        table.insert(cur_parts, tonumber(part) or 0)
    end
    local lat_parts = {}
    for part in lat:gmatch("[^.]+") do
        table.insert(lat_parts, tonumber(part) or 0)
    end

    for i = 1, math.max(#cur_parts, #lat_parts) do
        local cur_part = cur_parts[i] or 0
        local lat_part = lat_parts[i] or 0
        if lat_part > cur_part then
            return true
        elseif lat_part < cur_part then
            return false
        end
    end
    return false
end

-- Show notification
local function showMsg(text, timeout)
    UIManager:show(Notification:new{
        text = text,
        timeout = timeout or 2,
    })
end

-- Download update
local function downloadUpdate(download_url)
    local zip_path
    if is_android then
        zip_path = _plugin_dir .. "quickui.koplugin.zip"
    else
        zip_path = "/tmp/quickui.koplugin.zip"
    end

    local cmd = string.format("curl -L --max-time 15 -o '%s' '%s' 2>/dev/null", zip_path, download_url)
    local result = os.execute(cmd)

    if result ~= 0 then
        cmd = string.format("wget --timeout=15 -O '%s' '%s' 2>/dev/null", zip_path, download_url)
        result = os.execute(cmd)
    end

    if result ~= 0 then
        cmd = string.format("busybox wget --timeout=15 -O '%s' '%s' 2>/dev/null", zip_path, download_url)
        result = os.execute(cmd)
    end

    if result ~= 0 then
        os.remove(zip_path)
        return nil, _("Download failed")
    end

    local size = lfs.attributes(zip_path, "size") or 0
    if size < 1000 then
        showMsg(_("Downloaded file is invalid"), 3)
        os.remove(zip_path)
        return nil, _("Downloaded file is invalid")
    end

    return zip_path
end

-- Install update
local function installUpdate(zip_path)
    local install_dir = _plugin_dir:sub(1, -2)

    if is_android then
        if lfs.attributes(install_dir, "mode") ~= "directory" then
            os.execute("mkdir -p " .. install_dir)
        end

        local result = os.execute(string.format("unzip -o -q '%s' -d '%s' 2>/dev/null", zip_path, install_dir))

        if result ~= 0 then
            result = os.execute(string.format("busybox unzip -o -q '%s' -d '%s' 2>/dev/null", zip_path, install_dir))
        end

        os.remove(zip_path)

        if result == 0 then
            logger.info("QuickUI Updates: Auto-install successful")
            return true
        else
            logger.warn("QuickUI Updates: Auto-install failed")
            return false
        end
    else
        local result = os.execute(string.format("unzip -o %s -d %s", zip_path, install_dir))

        if result ~= 0 then
            result = os.execute(string.format("/usr/bin/unzip -o %s -d %s", zip_path, install_dir))
        end

        os.remove(zip_path)

        if result == 0 then
            logger.info("QuickUI Updates: Update installed successfully")
        else
            logger.warn("QuickUI Updates: Update installation failed")
        end

        return result == 0
    end
end

-- Version selection dialog
local _version_dialog = nil

local function showVersionChoice(versions, current_version, source)
    local ButtonDialog = require("ui/widget/buttondialog")
    local buttons = {}

    for i, v in ipairs(versions) do
        local is_current = (v.tag == current_version)
        local display_text = v.tag
        if v.source then
            display_text = display_text .. " [" .. v.source .. "]"
        end
        local button_text = is_current and
            string.format(_("Current version: %s (re-download)"), display_text) or
            string.format(_("Downgrade to %s"), display_text)

        table.insert(buttons, {
            {
                text = button_text,
                callback = function()
                    if _version_dialog then
                        UIManager:close(_version_dialog)
                        _version_dialog = nil
                    end
                    Updates.performUpdate(v.url, v.tag, source)
                end
            }
        })
    end

    table.insert(buttons, {})
    table.insert(buttons, {
        {
            text = _("Cancel"),
            callback = function()
                if _version_dialog then
                    UIManager:close(_version_dialog)
                    _version_dialog = nil
                end
            end
        }
    })

    _version_dialog = ButtonDialog:new{
        title = _("Select version to download"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
    }
    UIManager:show(_version_dialog)
end

-- Source selection dialog
local function showSourceSelectionDialog(on_selected)
    local ButtonDialog = require("ui/widget/buttondialog")
    local saved_key = getSourceKey()

    local dialog
    local buttons = {
        {
            {
                text = (saved_key == "github_latest" and "✓ " or "  ") .. _("GitHub (Latest)"),
                callback = function()
                    UIManager:close(dialog)
                    saveSource("github_latest")
                    if on_selected then on_selected(getSourceByKey("github_latest")) end
                end
            }
        },
        {
            {
                text = (saved_key == "github_prerelease" and "✓ " or "  ") .. _("GitHub (Pre-release)"),
                callback = function()
                    UIManager:close(dialog)
                    saveSource("github_prerelease")
                    if on_selected then on_selected(getSourceByKey("github_prerelease")) end
                end
            }
        },
        {
            {
                text = (saved_key == "gitee_latest" and "✓ " or "  ") .. _("Gitee (Latest)"),
                callback = function()
                    UIManager:close(dialog)
                    saveSource("gitee_latest")
                    if on_selected then on_selected(getSourceByKey("gitee_latest")) end
                end
            }
        },
        {},
        {
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end
            }
        },
    }

    dialog = ButtonDialog:new{
        title = _("Select update source"),
        title_align = "center",
        buttons = buttons,
        width = math.floor(Screen:getWidth() * 0.7),
    }
    UIManager:show(dialog)
end

-- Perform update check
local function doCheckUpdates(source)
    if not NetworkMgr:isOnline() then
        showMsg(_("No network connection, cannot check for updates"), 2)
        return
    end

    showMsg(_("Checking for updates..."), 1)

    UIManager:scheduleIn(0.5, function()
        local latest_version, download_url, source_used, err = getLatestVersionFromSource(source)

        if not latest_version then
            showMsg(err or _("Check for updates failed"), 3)
            return
        end

        local current_version = getCurrentVersion()

        if isNewerVersion(current_version, latest_version) then
            local source_text = " (" .. source_used .. ")"
            local message = string.format(_("New version found: %s%s\nCurrent version: %s\n\nDownload and install update?"),
                latest_version, source_text, current_version)

            UIManager:show(ConfirmBox:new{
                text = message,
                ok_text = _("Update"),
                cancel_text = _("Later"),
                ok_callback = function()
                    Updates.performUpdate(download_url, latest_version, source)
                end
            })
        else
            UIManager:show(ConfirmBox:new{
                text = string.format(_("Current version is up to date (%s)\n\nDowngrade to a previous version?"),
                    current_version),
                ok_text = _("Downgrade"),
                cancel_text = _("Cancel"),
                ok_callback = function()
                    UIManager:show(InfoMessage:new{
                        text = _("Getting version list..."),
                        timeout = 1
                    })

                    UIManager:scheduleIn(0.5, function()
                        local all_versions = getAllVersionsFromSource(source)
                        if not all_versions or #all_versions == 0 then
                            showMsg(_("Failed to get version list"), 2)
                            return
                        end
                        showVersionChoice(all_versions, current_version, source)
                    end)
                end
            })
        end
    end)
end

--[[
Public API: Check for updates
]]
function Updates.checkForUpdates(silent, plugin_ref)
    plugin = plugin_ref or plugin
    showSourceSelectionDialog(function(selected_source)
        doCheckUpdates(selected_source)
    end)
end

--[[
Public API: Perform update
]]
function Updates.performUpdate(download_url, target_version, source)
    if not download_url then
        UIManager:show(Notification:new{
            text = _("Update package download URL not found"),
            timeout = 2
        })
        return
    end

    local version_text = target_version and (" (" .. target_version .. ")") or ""
    local source_text = source and (" [" .. source.name .. "]") or ""

    UIManager:show(Notification:new{
        text = _("Downloading update") .. version_text .. source_text .. "...",
        timeout = 1
    })

    UIManager:scheduleIn(0.1, function()
        local zip_path, err = downloadUpdate(download_url)

        if not zip_path then
            UIManager:show(Notification:new{
                text = err or _("Download failed, please check network connection and try again"),
                timeout = 4
            })
            return
        end

        UIManager:show(Notification:new{
            text = _("Installing update") .. version_text .. "...",
            timeout = 1
        })

        UIManager:scheduleIn(0.1, function()
            local success = installUpdate(zip_path)

            if success then
                UIManager:show(ConfirmBox:new{
                    text = _("Update installed successfully. KOReader needs to restart to apply changes. Restart now?"),
                    ok_text = _("Restart"),
                    cancel_text = _("Later"),
                    ok_callback = function()
                        UIManager:restartKOReader()
                    end
                })
            else
                if is_android then
                    local data_dir = DataStorage:getDataDir()
                    if data_dir:sub(1, 2) == "./" then
                        data_dir = data_dir:sub(3)
                    elseif data_dir:sub(1, 1) == "." then
                        data_dir = data_dir:sub(2)
                    end
                    UIManager:show(Notification:new{
                        text = string.format(_("Automatic installation failed. Please manually extract %splugins/quickui.koplugin.zip to the plugins directory and restart"),
                            data_dir),
                        timeout = 5
                    })
                else
                    UIManager:show(Notification:new{
                        text = _("Installation failed, please update manually"),
                        timeout = 3
                    })
                end
            end
        end)
    end)
end

--[[
Public API: Init
]]
function Updates.init(plugin_ref)
    plugin = plugin_ref or plugin
    logger.info("QuickUI Updates: initialized")
end

return Updates
