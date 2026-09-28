--[[
QuickUI - WeRead metadata provider (Agent Gateway)

Uses WeRead's official Agent Gateway API (requires API Key).
Gateway: POST https://i.weread.qq.com/api/agent/gateway
Auth:    Authorization: Bearer wrk-xxxxxxxx

Search: api_name="/store/search", keyword, count
Detail: api_name="/book/info",     bookId

Returns the same draft structure as other QuickUI metadata providers.
]]

local json = require("json")
local Http = require("qui_metadata.qm_http")
local util = require("util")
local logger = require("logger")
local _ = require("gettext")

local M = {}

local GATEWAY_HOST = "i.weread.qq.com"
local GATEWAY_URL = "https://i.weread.qq.com/api/agent/gateway"
local SKILL_VERSION = "1.0.4"   -- 官方当前版本，回包出现 upgrade_info 时需更新
local SEARCH_LIMIT = 10
local MAX_QUERY_LENGTH = 256

-- ============================================================
-- Helpers
-- ============================================================

local function trim(value)
    return type(value) == "string" and (value:match("^%s*(.-)%s*$") or "") or ""
end

local function string_list(value)
    if type(value) == "string" then
        value = trim(value)
        if value == "" then return {} end
        -- 先把中文标点替换成 ASCII 逗号，再按 ASCII 拆
        value = value:gsub("，", ",")
        value = value:gsub("、", ",")
        value = value:gsub("；", ",")
        local result = {}
        for part in value:gmatch("[^,/]+") do
            part = trim(part)
            if part ~= "" then result[#result + 1] = part end
        end
        return #result > 0 and result or { value }
    end
    if type(value) == "table" then
        local result = {}
        for _i, item in ipairs(value) do
            item = trim(item)
            if item ~= "" then result[#result + 1] = item end
        end
        return result
    end
    return {}
end

local function cover_url(url)
    url = trim(url)
    if url == "" then return nil end
    if url:sub(1, 2) == "//" then return "https:" .. url end
    if url:sub(1, 7) ~= "http://" and url:sub(1, 8) ~= "https://" then return nil end
    return url
end

-- ============================================================
-- Normalize a book row from search/info into a "work"
-- ============================================================

local function normalize_book(row)
    if type(row) ~= "table" then return nil end

    local book_id = trim(row.bookId or row.book_id or row.id)
    local title = trim(row.title or row.bookName)
    if book_id == "" or title == "" then return nil end

    return {
        id = book_id,
        title = title,
        authors = string_list(row.author or row.authors),
        publisher = trim(row.publisher),
        isbn = trim(row.isbn),
        category = trim(row.category),
        intro = trim(row.intro or row.description),
        publishTime = (function()
            local t = trim(row.publishTime or row.publishDate)
            return t:match("^(%d%d%d%d%-%d%d%-%d%d)") or t
        end)(),
        rating = (function()
            local r = tonumber(row.newRating or row.rating)
            if r and r > 10 then return r / 100 end
            return r
        end)(),
        rating_count = tonumber(row.newRatingCount),
        word_count = tonumber(row.wordCount or row.totalWords),
        cover_url = cover_url(row.cover),
        _provider = "weread",
    }
end

-- ============================================================
-- Gateway call
-- ============================================================

local function gateway_call(api_key, api_name, params, transport)
    local body = { api_name = api_name, skill_version = SKILL_VERSION }
    for k, v in pairs(params or {}) do
        body[k] = v
    end

    local response, err = Http.request{
        url = GATEWAY_URL,
        host = GATEWAY_HOST,
        method = "POST",
        headers = {
            ["Authorization"] = "Bearer " .. api_key,
            ["Content-Type"] = "application/json",
        },
        body = json.encode(body),
    }
    if not response then
        return nil, err
    end

    local data, decode_err = Http.decodeJson(response)
    if not data then
        return nil, decode_err
    end

    -- 检查 upgrade_info：服务端要求升级 skill_version
    if data.upgrade_info then
        local msg = data.upgrade_info.message or "skill_version out of date"
        logger.warn("[QuickUI weread] upgrade required:", msg)
        return nil, Http.failure("malformed", nil, nil)  -- 可扩展为专用错误
    end

    local errcode = tonumber(data.errcode or data.errCode)
    if errcode and errcode ~= 0 then
        return nil, { kind = "network", message = data.errmsg or data.errMsg }
    end

    return data
end

-- ============================================================
-- Search
-- ============================================================

function M.search(api_key, input, transport)
    if type(api_key) ~= "string" or api_key == "" then
        return nil, Http.failure("unauthorized")
    end
    if type(input) ~= "table" then
        return nil, Http.failure("malformed")
    end

    local keyword = trim(input.title or input.isbn or "")
    if keyword == "" then
        return nil, Http.failure("malformed")
    end
    if #keyword > MAX_QUERY_LENGTH then
        keyword = keyword:sub(1, MAX_QUERY_LENGTH)
    end

    local limit = math.max(1, math.min(
        math.floor(tonumber(input.limit) or SEARCH_LIMIT), 20))

    local data, err = gateway_call(api_key, "/store/search", {
        keyword = keyword,
        count = limit,
        scope = 10,
    }, transport)
    if not data then
        return nil, err
    end

    -- results[] → books[] → bookInfo
    local results = data.results or {}
    local works = {}
    for _i, group in ipairs(results) do
        local books = group.books or {}
        for _j, row in ipairs(books) do
            local info = row.bookInfo or row
            local work = normalize_book(info)
            if work then
                works[#works + 1] = work
            end
        end
    end

    if #works == 0 then
        return nil, Http.failure("no_match")
    end

    logger.dbg("[QuickUI weread] search complete works=", #works)
    return works
end

-- ============================================================
-- Editions — WeRead has one record per book
-- ============================================================

function M.editions(_key, work)
    if type(work) ~= "table" or not work.id then
        return nil, Http.failure("malformed")
    end
    return {{
        id = work.id,
        work_id = work.id,
        title = work.title,
        isbn = work.isbn,
        publisher = work.publisher,
        cover_url = work.cover_url,
    }}
end

-- ============================================================
-- Fetch detail (fills in fields that search may lack)
-- ============================================================

function M.fetch_work_detail(work, api_key, transport)
    if type(work) ~= "table" or not work.id then return work end

    local data, _err = gateway_call(api_key, "/book/info", {
        bookId = work.id,
    }, transport)
    if not data then return work end

    local book = data.book or data
    local detailed = normalize_book(book)
    if detailed then
        for k, v in pairs(detailed) do
            if v ~= nil and v ~= "" then work[k] = v end
        end
        work._detail = detailed
    end
    return work
end

-- ============================================================
-- Draft
-- ============================================================

function M.draft(work, _edition)
    local detail = work._detail or work
    return {
        title = detail.title or work.title,
        authors = detail.authors or work.authors or {},
        series_name = "",
        series_index = "",
        genres = detail.category and { detail.category } or {},
        language = "",
        publisher = detail.publisher or "",
        pubdate = detail.publishTime or "",
        description = detail.intro or "",
        isbn = detail.isbn or "",
    }
end

-- ============================================================
-- Provider contract
-- ============================================================

M.id = "weread"
M.name = _("WeRead")
M.requires_key = true
M.key_config = "metadata_weread_key"
M.cover_referer = "https://weread.qq.com/"

function M.downloadCover(url, destination, transport)
    url = cover_url(url)
    if not url then return nil, Http.failure("malformed") end
    local host = url:match("^https://([^/]+)")
    if not host then return nil, Http.failure("malformed") end
    return Http.download(url, destination, host, {
        ["Referer"] = "https://weread.qq.com/",
        ["Accept"] = "image/jpeg, image/png, image/webp, image/gif",
    }, transport)
end

function M.cover_url(work)
    local url = work.cover_url
    if type(url) ~= "string" or url == "" then return nil end
    -- t6/s_ 换成 t9 拿高清图
    url = url:gsub("/t6_", "/t9_")
    url = url:gsub("/s_", "/t9_")
    return url
end

return M
