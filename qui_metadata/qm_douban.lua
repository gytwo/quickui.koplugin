--[[
QuickUI - Douban metadata provider

Scrapes Douban HTML pages (no public API):
  search  → https://www.douban.com/search?cat=1001&q=<query>
  detail  → https://book.douban.com/subject/<id>/

Adapted from metadata.koplugin/metadata/providers/douban.lua.
Douban changes its markup occasionally; treat failures as "no match",
never as a hard error.
]]

local http = require("socket.http")
local socket = require("socket")
local socketutil = require("socketutil")
local socket_url = require("socket.url")
local htmlparser = require("htmlparser")
local util = require("util")
local logger = require("logger")
local _ = require("gettext")

local M = {}

local USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    .. "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/98.0.4758.102 Safari/537.36"

local SEARCH_URL = "https://www.douban.com/search"
local SUBJECT_URL = "https://book.douban.com/subject/%s/"

-- ============================================================
-- HTTP
-- ============================================================

local function httpGet(url, params)
    local full_url = url
    if params then
        local parts = {}
        for k, v in pairs(params) do
            table.insert(parts, socket_url.escape(k) .. "=" .. socket_url.escape(v))
        end
        full_url = url .. "?" .. table.concat(parts, "&")
    end

    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local sink = {}
    local ok, code, headers, status = pcall(function()
        return socket.skip(1, http.request{
            url     = full_url,
            method  = "GET",
            headers = {
                ["User-Agent"]      = USER_AGENT,
                ["Accept-Encoding"] = "identity",
                ["Accept-Language"] = "zh-CN,zh;q=0.9,en;q=0.8",
                ["Referer"]         = "https://book.douban.com/",
            },
            sink    = socketutil.table_sink(sink),
        })
    end)
    socketutil:reset_timeout()

    if not ok then
        return nil, tostring(code)
    end
    if tonumber(code) ~= 200 then
        return nil, "HTTP " .. tostring(status or code or headers or "request failed")
    end
    return table.concat(sink)
end

-- ============================================================
-- Text helpers
-- ============================================================

local function trim(s)
    return (s or ""):gsub("&nbsp;", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function htmlEntitiesToUtf8(s)
    local ok, text = pcall(util.htmlEntitiesToUtf8, s or "")
    return ok and text or (s or "")
end

local function plainText(s, multiline)
    if not s then
        return nil
    end

    local text = htmlEntitiesToUtf8(s)

    -- Pass 1: normalize paragraph breaks to "\n" while the tags are
    -- still present. Done BEFORE htmlToPlainTextIfHtml, which would
    -- otherwise strip the tags and merge everything onto one line.
    if multiline then
        text = text:gsub("</p>%s*<p[^>]*>", "</p>\n<p")
        text = text:gsub("<br%s*/?>", "\n")
    end

    -- Strip comments, scripts, styles.
    text = text:gsub("<!%-%-[%s%S]-%-%->", " ")
    text = text:gsub("<%s*script[^>]*>[%s%S]-</%s*script%s*>", " ")
    text = text:gsub("<%s*style[^>]*>[%s%S]-</%s*style%s*>", " ")

    -- Pass 2: catch any leftover <p> tags (some Douban pages only
    -- emit opening/closing tags without adjacent siblings).
    if multiline then
        text = text:gsub("<%s*/%s*p%s*>%s*<%s*p[^>]*>", "</p>\n<p>")
        text = text:gsub("<%s*/%s*p%s*>", "\n")
        text = text:gsub("<%s*p[^>]*>", "")
    end

    text = util.htmlToPlainTextIfHtml(text)
    text = htmlEntitiesToUtf8(text)

    -- Strip whatever the util helper left behind.
    text = text:gsub("<!%-%-[%s%S]-%-%->", " ")
    text = text:gsub("<%s*script[^>]*>[%s%S]-</%s*script%s*>", " ")
    text = text:gsub("<%s*style[^>]*>[%s%S]-</%s*style%s*>", " ")
    text = text:gsub("<[^>]+>", " ")

    if multiline then
        text = text:gsub("[ \t\r\f\v]+", " ")
        text = text:gsub(" *\n+ *", "\n")
        text = text:gsub("\n+", "\n")
        text = text:match("^%s*(.-)%s*$")
    else
        text = trim(text)
    end
    text = text:gsub("^[:：]%s*", "")
    return text
end

local function stripTags(s)
    return plainText(s, false)
end

local function cleanLabel(label)
    return plainText(label, false):gsub("：$", ""):gsub(":$", "")
end

local function addDisplayLine(lines, label, value)
    if value and #value > 0 then
        table.insert(lines, { label = label, value = value })
    end
end

local function addTextSection(sections, title, text)
    if text and #text > 0 then
        table.insert(sections, { title = title, text = text })
    end
end

local function getAttribute(node, name)
    return node and node.attributes and node.attributes[name]
end

local function parseHtml(html)
    local ok, root = pcall(htmlparser.parse, html, 5000)
    return ok and root or nil
end

local function selectNodes(node, selector)
    if not node then return {} end
    local ok, nodes = pcall(function() return node:select(selector) end)
    return ok and nodes or {}
end

local function nodeText(node)
    if not node then return "" end
    local ok, text = pcall(function() return node:gettext() end)
    return ok and text or ""
end

local function nodeContent(node)
    if not node then return "" end
    local ok, content = pcall(function() return node:getcontent() end)
    return ok and content or ""
end

local function extractIntroAfterHeading(html, heading)
    local after_heading = html:match("<span>%s*" .. heading .. "%s*</span>(.*)")
    if not after_heading then return nil end
    local intro = after_heading:match('<span class="all[^"]*"[^>]*>(.-)</span>')
        or after_heading:match('<span class="short[^"]*"[^>]*>(.-)</span>')
        or after_heading:match('<div class="intro"[^>]*>(.-)</div>')
    return plainText(intro, true)
end

local function cleanDate(date)
    local year = date and date:match("^(%d%d%d%d)")
    if not year then return trim(date) end

    local parts = {}
    for number in date:sub(5):gmatch("%d+") do
        table.insert(parts, string.format("%02d", tonumber(number)))
        if #parts == 2 then break end
    end
    return string.format("%s-%s-%s", year, parts[1] or "01", parts[2] or "01")
end

-- ============================================================
-- Language normalization
-- ============================================================

local function normalize_language(text)
    if not text or text == "" then return nil end
    local t = text:lower()
    local map = {
        ["简体中文"] = "zh",
        ["繁体中文"] = "zh",
        ["中文"]     = "zh",
        ["汉语"]     = "zh",
        ["英语"]     = "en",
        ["英文"]     = "en",
        ["日语"]     = "ja",
        ["日文"]     = "ja",
        ["法语"]     = "fr",
        ["法文"]     = "fr",
        ["德语"]     = "de",
        ["德文"]     = "de",
        ["西班牙语"] = "es",
        ["俄语"]     = "ru",
        ["俄文"]     = "ru",
        ["韩语"]     = "ko",
        ["韩文"]     = "ko",
        ["意大利语"] = "it",
        ["葡萄牙语"] = "pt",
    }
    for key, code in pairs(map) do
        if t:find(key, 1, true) then
            return code
        end
    end
    if t:match("^[a-z][a-z][a-z%-]*$") then
        return text
    end
    return text
end

local function addCoverCandidate(candidates, seen, url, label, source)
    if type(url) ~= "string" or url == "" then return end
    url = htmlEntitiesToUtf8(url)
    if not url:match("^https?://") or seen[url] then return end
    seen[url] = true
    table.insert(candidates, { url = url, label = label, source = source })
end

local function largerCoverUrl(url)
    if type(url) ~= "string" then return nil end
    return url:gsub("/view/subject/s/public/", "/view/subject/l/public/")
end

-- ============================================================
-- Search
-- ============================================================

function M.search(_key, input)
    local title = type(input) == "table" and input.title or nil
    if not title or title == "" then
        return nil, { kind = "malformed" }
    end

    local html, err = httpGet(SEARCH_URL, { cat = "1001", q = title })
    if not html then
        logger.dbg("[QuickUI douban] search http error:", err)
        return nil, { kind = "network" }
    end

    local root = parseHtml(html)
    if not root then
        return nil, { kind = "malformed" }
    end

    local items = selectNodes(root, "div.result-list div.result")
    if #items == 0 then
        return nil, { kind = "no_match" }
    end

    local works = {}
    for _i, item in ipairs(items) do
        local result = {}
        local nbg_links = selectNodes(item, "a.nbg")
        if #nbg_links > 0 then
            local onclick = getAttribute(nbg_links[1], "onclick") or ""
            local sid = onclick:match("sid: (%d+)")
            if sid then
                result.id = sid
            end
            result.title = plainText(getAttribute(nbg_links[1], "title"), false)
        end

        local cover_imgs = selectNodes(item, "a.nbg img")
        if #cover_imgs > 0 then
            local cover_url = getAttribute(cover_imgs[1], "src")
            result.cover_url = largerCoverUrl(cover_url) or cover_url
        end

        local cast_spans = selectNodes(item, "span.subject-cast")
        if #cast_spans > 0 then
            result.author = plainText(nodeText(cast_spans[1]), false)
        end

        local rating_spans = selectNodes(item, "span.rating_nums")
        if #rating_spans > 0 then
            local rating_text = nodeText(rating_spans[1]):match("^%s*(.-)%s*$")
            local rating = tonumber(rating_text)
            if rating then
                result.rating = rating
            end
        end

        if result.id then
            table.insert(works, {
                id = result.id,
                title = result.title or title,
                authors = result.author and { result.author } or nil,
                rating = result.rating,
                image_url = result.cover_url,
                _douban = result,
            })
        end
    end

    if #works == 0 then
        return nil, { kind = "no_match" }
    end
    logger.dbg("[QuickUI douban] search complete works=", #works)
    return works
end

-- ============================================================
-- Editions — Douban has a single record per work, so wrap it.
-- ============================================================

function M.editions(_key, work)
    if type(work) ~= "table" then
        return nil, { kind = "malformed" }
    end
    return {{
        id = work.id,
        work_id = work.id,
        title = work.title,
        image_url = work.image_url,
    }}
end

-- ============================================================
-- Detail
-- ============================================================

function M.fetchDetail(id, search_result)
    local url = string.format(SUBJECT_URL, id)
    local html, err = httpGet(url)
    if not html then
        logger.dbg("[QuickUI douban] detail http error:", err)
        return nil, { kind = "network" }
    end

    local meta = {}
    local root = parseHtml(html)
    if not root then
        return nil, { kind = "malformed" }
    end

    -- Title
    local title_nodes = selectNodes(root, 'span[property="v:itemreviewed"]')
    if #title_nodes > 0 then
        meta.title = plainText(nodeText(title_nodes[1]), false)
    end

    local subtitle
    local subtitle_nodes = selectNodes(root, 'span[property="v:subtitle"]')
    if #subtitle_nodes > 0 then
        subtitle = plainText(nodeText(subtitle_nodes[1]), false)
    end

    -- Cover
    local cover_candidates = {}
    local seen_cover_urls = {}

    local cover_nodes = selectNodes(root, "#mainpic a.nbg")
    if #cover_nodes > 0 then
        addCoverCandidate(cover_candidates, seen_cover_urls,
            getAttribute(cover_nodes[1], "href"),
            "Detail page large image", "detail_mainpic_href")
    end

    local cover_img_nodes = selectNodes(root, "#mainpic img")
    if #cover_img_nodes > 0 then
        local img = cover_img_nodes[1]
        addCoverCandidate(cover_candidates, seen_cover_urls,
            largerCoverUrl(getAttribute(img, "src")),
            "Detail page image", "detail_mainpic_img_large")
        addCoverCandidate(cover_candidates, seen_cover_urls,
            getAttribute(img, "src"),
            "Detail page image", "detail_mainpic_img")
        addCoverCandidate(cover_candidates, seen_cover_urls,
            getAttribute(img, "data-original"),
            "Detail page image", "detail_mainpic_data_original")
        addCoverCandidate(cover_candidates, seen_cover_urls,
            getAttribute(img, "data-src"),
            "Detail page image", "detail_mainpic_data_src")
    end

    local og_image = html:match('<meta%s+property="og:image"%s+content="([^"]+)"')
        or html:match("<meta%s+property='og:image'%s+content='([^']+)'")
    addCoverCandidate(cover_candidates, seen_cover_urls, og_image,
        "OpenGraph image", "detail_og_image")

    if search_result then
        addCoverCandidate(cover_candidates, seen_cover_urls,
            search_result.cover_url, "Search result image", "search_result_large")
    end

    if #cover_candidates > 0 then
        meta.cover_urls = cover_candidates
        meta.cover_url = cover_candidates[1].url
    end

    -- Rating
    local rating_nodes = selectNodes(root, "strong.ll.rating_num")
    if #rating_nodes > 0 then
        local rating_text = nodeText(rating_nodes[1]):match("^%s*(.-)%s*$")
        local rating = tonumber(rating_text)
        if rating then meta.rating = rating end
    end

    -- Tags
    local tag_nodes = selectNodes(root, "a.tag")
    if #tag_nodes > 0 then
        local tags = {}
        for _i, node in ipairs(tag_nodes) do
            local tag = plainText(nodeText(node), false)
            if tag and #tag > 0 then
                table.insert(tags, tag)
            end
        end
        if #tags > 0 then meta.keywords = tags end
    else
        local criteria = html:match("criteria = '([^']+)'")
        if criteria then
            local tags = {}
            for item in criteria:gmatch("7:([^|]+)") do
                if item:match("^/subject/") then break end
                table.insert(tags, plainText(item, false))
            end
            if #tags > 0 then meta.keywords = tags end
        end
    end

    -- Description
    local desc_nodes = selectNodes(root, "#link-report span.all div.intro")
    if #desc_nodes == 0 then
        desc_nodes = selectNodes(root, "#link-report div.intro")
    end
    if #desc_nodes > 0 then
        meta.description = plainText(nodeContent(desc_nodes[#desc_nodes]), true)
    end

    -- Fallback: grab the whole #link-report block if the intro
    -- divs weren't found (page variant without .all / .short).
    if not meta.description or #meta.description == 0 then
        local link_report = selectNodes(root, "#link-report")
        if #link_report > 0 then
            meta.description = plainText(nodeContent(link_report[1]), true)
        end
    end

    -- Info block
    local info_nodes = selectNodes(root, "#info")
    local info_block = #info_nodes > 0
        and nodeContent(info_nodes[1])
        or html:match('<div id="info"[^>]*>(.-)</div>')

    if info_block then
        local authors = {}
        local info_lines = {}
        local normalized_info = info_block:gsub("<br%s*/?>", "<br/>") .. "<br/>"

        for entry in normalized_info:gmatch("(.-)<br/>") do
            local label, rest = entry:match('<span class="pl">([^<]+)</span>%s*:?(.*)')
            if label then
                local clean_label = cleanLabel(label)
                rest = stripTags(rest)
                if rest and #rest > 0 then
                    addDisplayLine(info_lines, clean_label, rest)
                    if clean_label:find("作者") then
                        table.insert(authors, rest)
                    elseif not clean_label:find("译者") then
                        if clean_label:find("副标题") and (not subtitle or #subtitle == 0) then
                            subtitle = rest
                        elseif clean_label:find("出版社") then
                            meta.publisher = rest
                        elseif clean_label:find("出版年") then
                            meta.pubdate = cleanDate(rest)
                        elseif clean_label:find("丛书") then
                            meta.series = rest
                        elseif clean_label:find("ISBN") then
                            meta.identifiers = meta.identifiers or {}
                            meta.identifiers.isbn = rest:gsub("%s+", "")
                        elseif clean_label:find("统一书号") then
                            meta.identifiers = meta.identifiers or {}
                            meta.identifiers.isbn = rest:gsub("%s+", "")
                        elseif clean_label:find("原作语言") then
                            meta.language = normalize_language(rest)
                        elseif clean_label:find("语言") then
                            meta.language = meta.language or normalize_language(rest)
                        end
                    end
                end
            end
        end

        if #authors > 0 then meta.authors = authors end
        if #info_lines > 0 then
            meta.display_sections = { { lines = info_lines } }
        end

        if not subtitle or #subtitle == 0 then
            subtitle = info_block:match('<span class="pl">副标题:?</span>%s*:?(.-)<br%s*/?>')
            subtitle = stripTags(subtitle)
        end
        if subtitle and #subtitle > 0 then
            meta.title = (meta.title or "") .. "：" .. subtitle
        end
    end

    if meta.description then
        addTextSection(meta.display_sections or {}, "内容简介", meta.description)
    end
    local author_intro = extractIntroAfterHeading(html, "作者简介")
    if author_intro then
        meta.display_sections = meta.display_sections or {}
        addTextSection(meta.display_sections, "作者简介", author_intro)
    end

    meta.provider_id = "douban"
    meta.provider_name = M.name
    return meta
end

-- ============================================================
-- Provider contract
-- ============================================================

M.id = "douban"
M.name = _("Douban")
M.requires_key = false
M.cover_referer = "https://book.douban.com/"

function M.draft(work, edition)
    local detail = work._detail or work
    return {
        title        = detail.title or work.title,
        authors      = detail.authors or work.authors or {},
        series_name  = detail.series or "",
        series_index = detail.series_index or "",
        genres       = detail.keywords or {},
        language     = detail.language or "",
        publisher    = detail.publisher or "",
        description  = detail.description or "",
        isbn         = (detail.identifiers and detail.identifiers.isbn) or "",
    }
end

function M.fetch_work_detail(work)
    if type(work) ~= "table" or not work.id then
        return nil, { kind = "malformed" }
    end
    local meta, err = M.fetchDetail(work.id, work._douban)
    if not meta then
        return work, err
    end
    for k, v in pairs(meta) do
        work[k] = v
    end
    work._detail = meta
    return work
end

return M