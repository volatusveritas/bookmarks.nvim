----------------------------------
--    Local-global Variables    --
----------------------------------

local bookmarks = {}

-- The root of bookmarks.nvim's files and directories.
local bmks_location = vim.fs.normalize(vim.fn.stdpath("data"))

local bmks_file_name = "bookmarks"
local backups_folder_name = bmks_file_name .. "_backups"

local bmks_file_path = bmks_location .. "/" .. bmks_file_name
local backups_folder_path = bmks_location .. "/" .. backups_folder_name

-- The ID of bookmarks.nvim's autocommands group.
local bookmarks_augroup = vim.api.nvim_create_augroup("Bookmarks", {})

-- The ID of bookmarks.nvim's namespace.
local bookmarks_ns = vim.api.nvim_create_namespace("bookmarks.nvim")


----------------------------
--    Highlight Groups    --
----------------------------

vim.api.nvim_create_autocmd(
    "ColorScheme", {
        group = bookmarks_augroup,
        callback = function()
            -- For the "[bookmarks.nvim]" message starting tag
            vim.cmd("highlight BookmarksNvimTag gui=bold guifg=LightBlue")
            -- For the widgets' titles
            vim.cmd("highlight BookmarksNvimTitle gui=bold guifg=LightRed")
            -- For the widget's subtitles
            vim.cmd("highlight BookmarksNvimSubtitle guifg=Gray")
            -- For the bookmarks' names
            vim.cmd("highlight BookmarksNvimBookmark guifg=LightCyan")
        end,
    }
)


---------------------
--    Plugin UI    --
---------------------

local DOWNWARDS_ARROW = "▼"
local UPWARDS_ARROW = "▲"

local downwards_arrow_extmark = nil
local upwards_arrow_extmark = nil

local widget_frame = {
    -- The handle for the current widget's window.
    win = nil,
    -- The handle for the current widget's buffer.
    buf = nil,
    -- The next available line in the current widget window.
    next_line = 1 -- 1-based index
}

local widget_focus = {
    -- The handle for the current widget's focused window.
    win = nil,
    -- The handle for the current widget's focused buffer.
    buf = nil,
    -- The next available line in the current widget's focused window.
    next_line = 1 -- 1-based index
}

-- Reserved for bookmarks.nvim's future configuration capabilities.
-- TODO: Add a way to configure bookmarks.nvim.
local preferences = {
    widget = {
        size = {
            width = 80,
            height = 24
        }
    },
    listview_mode = {
        reset_cursor_on_scroll = true,
    },
}


-- Resets the cursor to the initial position inside the widget's window.
local function widget_cursor_reset(widget)
    vim.api.nvim_win_set_cursor(widget.win, { 1, 0 })
end

-- Centers all line numbers in the lines array without changing the cursor's
-- position.
local function widget_center_lines(widget, lines)
    vim.bo[widget.buf].modifiable = true

    for _, lnum in ipairs(lines) do
        local center_padding = string.rep(
            " ", math.ceil(
                (
                    preferences.widget.size.width
                    - #vim.api.nvim_buf_get_lines(
                        widget.buf, lnum - 1, lnum, false
                    )[1]
                ) / 2
            )
        )
        vim.api.nvim_buf_set_text(
            widget.buf,
            lnum - 1, 0,
            lnum - 1, 0,
            { center_padding }
        )
    end

    vim.bo[widget.buf].modifiable = false
end

-- Shortcut for widget_center_lines with one line only.
local function widget_center_line(widget, line)
    widget_center_lines(widget, { line })
end

-- Writes each element in the lines array in its own line, moving the cursor
-- downwards as it does it.
local function widget_write_lines(widget, lines)
    vim.bo[widget.buf].modifiable = true

    vim.api.nvim_buf_set_lines(
        widget.buf, widget.next_line - 1, widget.next_line - 1, false, lines
    )

    widget.next_line = widget.next_line + #lines

    vim.bo[widget.buf].modifiable = false
end

-- Shortcut for widget_write_lines with one line only.
local function widget_write_line(widget, line)
    widget_write_lines(widget, {line})
end

-- Initializes a buffer and a window for a widget.
local function widget_initialize(widget, win_opts)
    widget.next_line = 1

    widget.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[widget.buf].bufhidden = "wipe"
    vim.bo[widget.buf].filetype = "bookmarks-nvim"
    vim.bo[widget.buf].modifiable = false

    widget.win = vim.api.nvim_open_win(widget.buf, true, win_opts)
    vim.wo[widget.win].foldmethod = "manual"
end

-- Closes the widget's frame and focus.
local function widget_close()
    vim.api.nvim_win_close(widget_focus.win, false)
    vim.api.nvim_win_close(widget_frame.win, false)
end

local function widget_update_extmarks()
    if upwards_arrow_extmark then
        vim.api.nvim_buf_del_extmark(0, bookmarks_ns, upwards_arrow_extmark)
    end
    if downwards_arrow_extmark then
        vim.api.nvim_buf_del_extmark(0, bookmarks_ns, downwards_arrow_extmark)
    end

    local win_top = vim.fn.getpos("w0")[2]
    local win_bottom = win_top + vim.fn.winheight(widget_focus.win) - 1
    local win_lines = #vim.api.nvim_buf_get_lines(
        widget_focus.buf, 0, -1, false
    )

    if win_top > 1 then
        -- More above
        upwards_arrow_extmark = vim.api.nvim_buf_set_extmark(
            0, bookmarks_ns,
            win_top - 1, 0,
            {
                virt_text_pos = "overlay",
                virt_text_win_col = vim.fn.winwidth(0) - 1,
                virt_text = {
                    { UPWARDS_ARROW, "PreProc" },
                },
                strict = false,
            }
        )
    end

    if win_bottom < win_lines - 1 then
        -- More below
        downwards_arrow_extmark = vim.api.nvim_buf_set_extmark(
            0, bookmarks_ns,
            win_bottom - 1, 0,
            {
                virt_text_pos = "overlay",
                virt_text_win_col = vim.fn.winwidth(0) - 1,
                virt_text = {
                    { DOWNWARDS_ARROW, "PreProc" },
                },
                strict = false,
            }
        )
    end
end

-- Enables listview mode (maps j/k to screen scrolling, disables normal
-- conflicting editing options such as scrolloff).
local function widget_listview_mode()
    vim.wo[widget_focus.win].scrolloff = 0

    vim.api.nvim_create_autocmd("WinScrolled", {
        group = bookmarks_augroup,
        buffer = widget_focus.buf,
        callback = function()
            if preferences.listview_mode.reset_cursor_on_scroll then
                vim.cmd("normal H0")
            end

            widget_update_extmarks()
        end
    })

    vim.keymap.set("n", "j", function()
        local win_top = vim.fn.getpos("w0")[2]
        local win_lines = #vim.api.nvim_buf_get_lines(
            widget_focus.buf, 0, -1, false
        )

        if (
            win_top + vim.fn.winheight(widget_focus.win) - 1
            >= win_lines - 1
        ) then
            return
        end

        vim.cmd("normal! ")
    end, { buffer = 0 })

    vim.keymap.set("n", "k", "<C-y>", { buffer = 0 })

    vim.keymap.set("n", "J", "j", { buffer = 0, noremap = true })
    vim.keymap.set("n", "K", "k", { buffer = 0, noremap = true })

    widget_update_extmarks()
end

-- Creates the widget frame with a title.
local function create_widget_frame(widget_name)
    widget_name = widget_name or "Untitled"

    widget_initialize(widget_frame, {
        relative = "editor",
        width = preferences.widget.size.width,
        height = preferences.widget.size.height,
        col = (vim.o.columns - preferences.widget.size.width) / 2,
        row = (vim.o.lines - preferences.widget.size.height) / 2,
        style = "minimal",
        border = "rounded",
    })

    -- Initial contents
    widget_write_lines(widget_frame, {
        "[bookmarks.nvim] " .. widget_name,
        "",
        "[q], [Esc] -- close this window.",
        "[j]/[k] -- scroll down/up the item list.",
        "[J]/[K] -- normal behavior of [j]/[k].",
        ""
    })
    vim.api.nvim_buf_add_highlight(
        widget_frame.buf, bookmarks_ns, "BookmarksNvimTag",
        0, 0, #"[bookmarks.nvim]"
    )
    vim.api.nvim_buf_add_highlight(
        widget_frame.buf, bookmarks_ns, "BookmarksNvimTitle",
        0, #"[bookmarks.nvim] ", -1
    )
    for lnum = 2,4 do
        vim.api.nvim_buf_add_highlight(
            widget_frame.buf, bookmarks_ns, "BookmarksNvimSubtitle",
            lnum, 0, -1
        )
    end

    widget_center_lines(widget_frame, { 1, 3, 4, 5 })
end

-- Creates the widget focus.
local function create_widget_focus(
    top_offset, left_offset,
    bottom_offset, right_offset
)
    top_offset = top_offset or 6
    left_offset = left_offset or 1
    bottom_offset = bottom_offset or 1
    right_offset = right_offset or 1

    widget_initialize(widget_focus, {
        relative = "editor",
        width = preferences.widget.size.width - left_offset - right_offset,
        height = preferences.widget.size.height - top_offset - bottom_offset,
        col = (vim.o.columns - preferences.widget.size.width) / 2 + 1 + left_offset,
        row = (vim.o.lines - preferences.widget.size.height) / 2 + 1 + top_offset,
        style = "minimal",
    })
end

-- Shortcut that creates both a widget's frame and focus.
local function create_widget(
    widget_name,
    top_offset, left_offset,
    bottom_offset, right_offset
)
    widget_name = widget_name or "Untitled"

    create_widget_frame(widget_name)
    create_widget_focus(
        top_offset, left_offset,
        bottom_offset, right_offset
    )

    vim.keymap.set("n", "q", widget_close, { buffer = 0 })
    vim.keymap.set("n", "<Esc>", widget_close, { buffer = 0 })
end


-------------------------------
--    Auxiliary Functions    --
-------------------------------

-- Echoes msg without writing to :messages.
local function echo(msg)
    vim.api.nvim_echo(
        { { "[bookmarks.nvim] ", "BookmarksNvimTag" }, { msg } },
        false, {}
    )
end

-- Returns the passed string s without leading or trailing whitespace.
-- Credit to https://gist.github.com/ram-nadella/dd067dfeb3c798299e8d
local function trim(s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

-- Returns the passed string s without trailing whitespace.
-- Credit to https://gist.github.com/ram-nadella/dd067dfeb3c798299e8d
local function rtrim(s)
    return (string.gsub(s, "^(.-)%s*$", "%1"))
end

-- Returns true if a file exists. If it doesn't, creates it.
-- Returns false if creation fails, true otherwise.
local function ensure_file(file_name, file_dir)
    local file_path = file_dir .. "/" .. file_name

    if vim.fn.findfile(file_name, file_dir) == "" then
        if vim.fn.writefile({}, file_path) == -1 then
            echo(
                string.format(
                    "Unable to create the file '%s' at %s.",
                    file_name, file_path
                )
            )

            return false
        end
    end

    return true
end

-- Returns true if a folder exists. If it doesn't, creates it.
-- Returns false if creation fails, true otherwise.
local function ensure_folder(folder_name, folder_dir)
    local folder_path = folder_dir .. "/" .. folder_name

    if vim.fn.finddir(folder_name, folder_dir) == "" then
        if vim.fn.mkdir(folder_path) == 0 then
            echo(
                string.format(
                    "Unable to create the folder '%s' at %s.",
                    folder_name, folder_path
                )
            )

            return false
        end
    end

    return true
end

-- Collects bookmarks from the bookmarks file, overriding the bookmark list.
-- Returns false if file can't be read, true otherwise.
local function collect_bookmarks()
    local bmks_file = io.open(bmks_file_path)

    if not bmks_file then
        echo(
            string.format(
                "Unable to read from the bookmarks file at %s.",
                bmks_file_path
            )
        )

        return false
    end

    bookmarks = {}

    local next_line = bmks_file:read()
    while next_line do
        -- Format: bookmark_name|bookmark_path
        local pipe_index = string.find(next_line, "|", 1, true)
        local bookmark_name = string.sub(next_line, 1, pipe_index - 1)
        local bookmark_path = string.sub(next_line, pipe_index + 1)

        bookmarks[bookmark_name] = bookmark_path

        next_line = bmks_file:read()
    end

    bmks_file:close()

    return true
end

-- Stores bookmarks from the bookmark list in the bookmarks file.
-- Returns false if file can't be written to, true otherwise.
local function store_bookmarks(path)
    local bmks_file = io.open(path, "w+")

    if not bmks_file then
        echo(
            string.format(
                "Unable to write to the bookmarks file at %s.",
                bmks_file_path
            )
        )

        return false
    end

    for k,v in pairs(bookmarks) do
        local file, error = bmks_file:write(string.format("%s|%s\n", k, v))

        if not file then
            echo(
                string.format(
                    "Error when writing bookmark '%s': %s.",
                    k, error
                )
            )

            return false
        end
    end

    bmks_file:close()

    return true
end



----------------------------------
--    Interaction Functions     --
----------------------------------

-- Promps the creation of a new bookmark set to the current file.
local function make_bookmark()
    -- TODO: Make it so creating bkX when it exists creates bkX2.
    local file_name = vim.fn.expand("%:t:r")

    local bookmark_name = trim(vim.fn.input(
        string.format(
            "Bookmark name (leave empty to use '%s' as the name): ",
            file_name
        )
    ))

    if bookmark_name == "" then
        bookmark_name = file_name

        if bookmark_name == "" then
            echo("Empty bookmark name provided. Operation aborted.")
            return
        end
    end

    local overriden = false
    if bookmarks[bookmark_name] then
        local choice = vim.fn.confirm(
            string.format(
                "Bookmark '%s' already exists. Override it? [Default: Yes]",
                bookmark_name
            ),
            "&Yes\n&No", 1
        )

        if choice ~= 1 then
            return
        end

        overriden = true
    end

    local bookmark_path = vim.fs.normalize(vim.fn.expand("%:p"))
    bookmarks[bookmark_name] = bookmark_path

    local action = overriden and "overriden" or "made"
    echo(string.format("Bookmark '%s' was %s!", bookmark_name, action))
end

-- Displays unix-ls style list of bookmarks in columns, or a stacked list with
-- paths if verbose is true.
local function list_bookmarks(verbose)
    create_widget("Bookmark List")

    do
        local count = 0
        for _ in pairs(bookmarks) do
            count = count + 1
        end

        if count == 0 then
            widget_write_line(widget_focus, "No bookmarks found.")
            widget_center_line(widget_focus, 1)
        end
    end

    local column_amount = 3
    local division = string.rep(" ", 4)

    if verbose then
        for k, v in pairs(bookmarks) do
            widget_write_line(
                widget_focus,
                --[[string.rep(" ", 4) .. ]]k .. " -- " .. v
            )
        end

        widget_cursor_reset(widget_focus)
        widget_listview_mode()

        return
    end

    local bookmark_names = {}
    for key, _ in pairs(bookmarks) do
        table.insert(bookmark_names, key)
    end

    table.sort(bookmark_names)

    local remaining = #bookmark_names
    local current = 1

    local columns = {}

    for _ = 1, column_amount do
        table.insert(columns, { max_size = 0 })
    end

    local rows = math.ceil(#bookmark_names / column_amount)

    for c = 1, column_amount do
        local remaining_columns = column_amount - c + 1
        local amount_in_column = math.ceil(remaining / remaining_columns)

        for i = 0, amount_in_column - 1 do
            local index = current + i

            if #bookmark_names[index] > columns[c].max_size then
                columns[c].max_size = #bookmark_names[index]
            end

            table.insert(columns[c], bookmark_names[index])
        end

        current = current + amount_in_column
        remaining = remaining - amount_in_column
    end

    local bookmark_lines = {}
    local max_line = 0

    for row = 1, rows do
        local bookmarks_line = ""

        for col = 1, column_amount do
            if columns[col][row] then
                local pre_padding_size = math.ceil(
                    (columns[col].max_size - #columns[col][row]) / 2
                )
                local post_padding_size = (
                    columns[col].max_size - #columns[col][row] - pre_padding_size
                )

                bookmarks_line = bookmarks_line .. (
                    string.rep(" ", pre_padding_size)
                    .. columns[col][row]
                    .. string.rep(" ", post_padding_size)
                    .. division
                )
            else
                bookmarks_line = bookmarks_line .. (
                    string.rep(" ", columns[col].max_size)
                )
                .. division
            end
        end

        bookmarks_line = rtrim(bookmarks_line)

        if #bookmarks_line > max_line then
            max_line = #bookmarks_line
        end

        table.insert(bookmark_lines, bookmarks_line)
    end

    if max_line + (column_amount - 1) * #division > vim.fn.winwidth(0) then
    end

    local first_line = widget_focus.next_line
    widget_write_lines(widget_focus, bookmark_lines)

    local centering_padding = string.rep(
        " ", math.ceil((vim.fn.winwidth(0) - max_line) / 2)
    )

    -- TODO: Reduce the number of columns (min. 1) if it doesn't fit
    -- TODO: Follow api-indexing standard for widget_next_line
    vim.bo[widget_focus.buf].modifiable = true

    for lnum = first_line - 1, widget_focus.next_line - 2 do
        vim.api.nvim_buf_set_text(
            widget_focus.buf,
            lnum, 0,
            lnum, 0,
            { centering_padding }
        )

        vim.api.nvim_buf_add_highlight(
            widget_focus.buf, bookmarks_ns, "BookmarksNvimBookmark",
            lnum, 0, -1
        )
    end

    vim.bo[widget_focus.buf].modifiable = false

    widget_cursor_reset(widget_focus)

    widget_listview_mode()
end

-- Jumps to a bookmark by its name.
local function goto_bookmark(method)
    local target_bookmark = trim(
        vim.fn.input("Target bookmark: ")
    )

    if target_bookmark == "" then
        echo("Empty bookmark name provided. Operation aborted.")
        return
    end

    if not bookmarks[target_bookmark] then
        echo(string.format("Invalid bookmark '%s'.", target_bookmark))
        return
    end

    if method == "abuf" then
        vim.cmd(string.format("edit %s", bookmarks[target_bookmark]))
    elseif method == "horizontal" then
        vim.cmd(string.format("split %s", bookmarks[target_bookmark]))
    elseif method == "vertical" then
        vim.cmd(string.format("vsplit %s", bookmarks[target_bookmark]))
    elseif method == "tab" then
        vim.cmd(string.format("tabedit %s", bookmarks[target_bookmark]))
    end
end

-- Deletes a bookmark from the bookmark list.
local function delete_bookmark()
    local target_bookmark = vim.fn.input(
        "Target bookmark: "
    )

    if not bookmarks[target_bookmark] then
        echo(string.format("Invalid bookmark '%s'.", target_bookmark))
        return
    end

    bookmarks[target_bookmark] = nil

    echo(string.format("Bookmark '%s' deleted!", target_bookmark))
end

-- Writes the bookmarks to the bookmarks file and makes a new backup in the
-- backups folder.
local function backup_bookmarks()
    local backup_file_name = bmks_file_name .. "_" .. vim.fn.localtime()
    local backup_file_path = backups_folder_path .. "/" .. backup_file_name

    if not store_bookmarks(bmks_file_path) then
        return
    end

    if not store_bookmarks(backup_file_path) then
        return
    end

    echo(
        string.format(
            "Bookmarks backup file '%s' was created at %s.",
            backup_file_name, backup_file_path
        )
    )
end

-- Deletes all backups from the backups folder, then makes a new backup.
local function overwrite_backups()
    for f, t in vim.fs.dir(backups_folder_path) do
        local path = backups_folder_path .. "/" .. f
        vim.notify(path)
        if t == "file" then
            if vim.fn.delete(path) == -1 then
                vim.notify(
                    string.format(
                        "Error while trying to delete file '%s'.",
                        path
                    )
                )
            end
        end
    end

    backup_bookmarks()

    vim.notify(string.format("Bookmarks overwritten."))
end

-- Prompts the reset of the bookmarks and the bookmarks file (doesn't affect
-- backups).
local function reset_bookmarks()
    local choice = vim.fn.confirm(
        "Are you sure you want to reset your bookmarks?"
        .." You are going to lose ALL bookmarks."
        .." Consider making a backup of your bookmarks file."
        .." [Default: Yes]",
        "&Yes\n&No", 1
    )

    if choice ~= 1 then
        return
    end

    bookmarks = {}
    store_bookmarks(bmks_file_path)

    echo("Bookmarks were reset!")
end

-- Recollects bookmarks from the bookmarks file.
local function reload_bookmarks()
    if not collect_bookmarks() then
        return
    else
        echo("Reloaded bookmarks!")
    end
end

-- Writes the bookmarks to the bookmarks file.
local function write_bookmarks()
    if not store_bookmarks(bmks_file_path) then
        return
    end

    echo("Written to the bookmarks file!")
end



---------------------------
--    On-require code    --
---------------------------

ensure_file(bmks_file_name, bmks_location)
ensure_folder(backups_folder_name, bmks_location)
collect_bookmarks()


vim.keymap.set("n", "gbm", make_bookmark)
vim.keymap.set("n", "gbd", delete_bookmark)
vim.keymap.set("n", "gbb", backup_bookmarks)
vim.keymap.set("n", "gbB", overwrite_backups)
vim.keymap.set("n", "gbR", reset_bookmarks)
vim.keymap.set("n", "gbr", reload_bookmarks)
vim.keymap.set("n", "gbw", write_bookmarks)

vim.keymap.set("n", "gbg", function() goto_bookmark("abuf") end)
vim.keymap.set("n", "gbx", function() goto_bookmark("horizontal") end)
vim.keymap.set("n", "gbv", function() goto_bookmark("vertical") end)
vim.keymap.set("n", "gbt", function() goto_bookmark("tab") end)

vim.keymap.set("n", "gbl", function() list_bookmarks(false) end)
vim.keymap.set("n", "gbL", function() list_bookmarks(true) end)


vim.api.nvim_create_autocmd(
    "VimLeave",
    {
        group=bookmarks_augroup,
        callback=function() store_bookmarks(bmks_file_path) end,
    }
)

-- TODO: Add bookmark renaming functionality (gbc "bookmark change"?)
-- TODO: Add a way to recover a backup from withing Neovim (gbf "bookmark fetch"?)
