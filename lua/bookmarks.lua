local function echo(msg)
    vim.api.nvim_echo({{msg}}, false, {})
end


local bookmarks = {}

local bmks_location = vim.fs.normalize(vim.fn.stdpath("data"))

local bmks_file_name = "bookmarks"
local backup_folder_name = bmks_file_name .. "_backups"

local bmks_file_path = bmks_location .. "/" .. bmks_file_name
local backup_folder_path = bmks_location .. "/" .. backup_folder_name



-------------------------------
--    Auxiliary Functions    --
-------------------------------

-- Returns the passed string s without leading or trailing whitespace.
-- Credit to https://gist.github.com/ram-nadella/dd067dfeb3c798299e8d
local function trim(s)
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
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

-- Returns a formatted string, unix-ls style list of bookmarks in columns, or a
-- unidirectional list with paths if verbose is true.
local function get_bookmark_list(verbose)
    do
        local count = 0
        for _ in pairs(bookmarks) do
            count = count + 1
        end

        if count == 0 then
            return "No bookmarks found."
        end
    end

    local padding = string.rep(" ", 4)
    local division = string.rep(" ", 2)

    local bookmarks_str = "Bookmarks:\n"

    if verbose then
        for k, v in pairs(bookmarks) do
            bookmarks_str = bookmarks_str .. string.format(
                "%s%s -- %s\n",
                padding, k, v
            )
        end

        return bookmarks_str
    end

    local row_amount = math.ceil(#bookmarks / 4)

    if row_amount == 1 then
        bookmarks_str = padding
        for k, _ in pairs(bookmarks) do
            bookmarks_str = bookmarks_str .. k .. "  "
        end
    else
        local bookmark_names = {}
        for key, _ in pairs(bookmarks) do
            table.insert(bookmark_names, key)
        end

        table.sort(bookmark_names)

        local remaining = #bookmark_names
        local current = 1

        local columns = {
            { maxsize = 0 },
            { maxsize = 0 },
            { maxsize = 0 },
            { maxsize = 0 }
        }

        local rows = math.ceil(#bookmark_names / 4)

        for c = 1, 4 do
            local remaining_columns = 4 - c + 1
            local amount_in_column = math.ceil(remaining / remaining_columns)

            for i = 0, amount_in_column - 1 do
                local index = current + i

                if #bookmark_names[index] > columns[c].maxsize then
                    columns[c].maxsize = #bookmark_names[index]
                end

                table.insert(columns[c], bookmark_names[index])
            end

            current = current + amount_in_column
            remaining = remaining - amount_in_column
        end

        for row = 1, rows do
            bookmarks_str = bookmarks_str .. padding

            for col = 1, 4 do
                if columns[col][row] then
                    bookmarks_str = bookmarks_str .. (
                        columns[col][row] .. string.rep(
                            " ",
                            columns[col].maxsize - #columns[col][row]
                        )
                        .. division
                    )
                else
                    bookmarks_str = bookmarks_str .. (
                        string.rep(" ", columns[col].maxsize)
                    )
                    .. division
                end
            end

            bookmarks_str = bookmarks_str .. "\n"
        end
    end

    return bookmarks_str
end



----------------------------------
--    Interaction Functions     --
----------------------------------

-- Promps the creation of a new bookmark set to the current file.
local function make_bookmark()
    local file_name = vim.fn.expand("%:t:r")

    local bookmark_name = trim(vim.fn.input(
        get_bookmark_list(false)
        .. string.format(
            "\nBookmark name (leave empty to use '%s' as the name): ",
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

-- Lists the available bookmarks from the bookmark list.
local function list_bookmarks(verbose)
    echo(get_bookmark_list(verbose))
end

-- Jumps to a bookmark by its name.
local function goto_bookmark(method)
    local target_bookmark = trim(
        vim.fn.input(
            get_bookmark_list(false) .. "\nTarget bookmark: "
        )
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
        get_bookmark_list(false) .. "\nTarget bookmark: "
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
    local backup_file_path = backup_folder_path .. "/" .. backup_file_name

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
    for f, t in vim.fs.dir(backup_folder_path) do
        local path = backup_folder_path .. "/" .. f
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
    if collect_bookmarks() then
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
ensure_folder(backup_folder_name, bmks_location)
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


local bookmarks_augroup = vim.api.nvim_create_augroup("Bookmarks", {})
vim.api.nvim_create_autocmd(
    "VimLeave",
    {
        group=bookmarks_augroup,
        callback=function() store_bookmarks(bmks_file_path) end,
    }
)
