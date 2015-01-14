-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
API
---
**parse_cbuf(cbuf_text)**

    Parses the circular buffer data such as that output by a SandboxFilter and
    returns a table of headers and an array containing the rows of data.

    *Arguments*
        - cbuf_text (string)
            String containing the textual circular buffer data. Usually the
            entire payload of a cbuf message generated by a SandboxFilter.

    *Return*
        - If parsing is successful, two values are returned:
          - headers:
            A table containing the header values of `time`, `rows`,
            `seconds_per_row`, `columns`, and `column_info`.
          - rows:
            An array or nested row arrays, where each row array contains the
            column values, in order, either as a number or as the string
            literal "nan". Note that the last row should typically not be
            used, as it is probably incomplete.
        - If parsing fails, or the header data isn't valid, nil is returned.

**get_start_idx(last_time, headers)**

    Given the timestamp of a previous cbuf payload and the headers from a more
    current cbuf payload, calculates the index of the first row of new data in
    the more current cbuf data set.

    *Arguments*
        - last_time (number)
            The `time` value retrieved from the headers table of the earlier
            cbuf data.
        - headers (table)
            The headers table (as returned from `parse_cbuf`) of the current
            cbuf data.

    *Return*

        - If calculations are successful, will return a positive integer
          number value corresponding to the index of the first row that
          contains new data since the previous cbuf time.
        - If the new cbuf time is the same as the provided last_time, will
          return -2.
        - If calculations fail (because last_time is more recent than new
          time, or because the time interval isn't exactly divisible by the
          cbuf's seconds_per_row value), will return -1.
--]]

local cjson = require "cjson"
local string = require "string"
local pcall = pcall
local tonumber = tonumber

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module.

local function check_headers(headers)
    if (not headers.time) or (not headers.rows) or (not headers.seconds_per_row)
        or (not headers.columns) or (not headers.column_info) then

        return
    end
    if headers.columns ~= #headers.column_info then
        return
    end
    return true
end

-- [[ Public Interface --]]

function parse_cbuf(cbuf_text)
    local rows = {}
    local headersText, headers, ok
    local first = true
    for row in string.gmatch(cbuf_text, "[^\n]+") do
        if first == true then
            -- Parse the headers.
            headersText = row
            ok, headers = pcall(cjson.decode, headersText)
            if not ok then
                return
            end
            -- Skip annotations line, if it exists.
            if not headers.annotations then
                if not check_headers(headers) then
                    return
                end
                first = false
            end
        else
            -- Parse the row values
            local values = {}
            for value in string.gmatch(row, "[^\t]+") do
                if value ~= "nan" then
                    value = tonumber(value)
                    if not value then
                        value = "nan"
                    end
                end
                values[#values+1] = value

            end
            rows[#rows+1] = values
        end
    end
    -- Last sanity check that headers match the actual row count.
    local num_rows = #rows
    if num_rows < 3 or num_rows ~= headers.rows then
        return
    end
    return headers, rows
end

function get_start_idx(last_time, headers)
    if not last_time then
        -- First time from this source, start from the first row.
        return 1
    end
    local time = headers.time
    if last_time > time then
        -- Invalid, error out.
        return -1
    end
    if last_time == time then
        -- Duplicate, ignore.
        return -2
    end
    local elapsed_time = time - last_time
    if elapsed_time % headers.seconds_per_row ~= 0 then
        -- Non-integer number of rows, no bueno.
        return -1
    end
    local rows_elapsed = elapsed_time / headers.seconds_per_row

    if rows_elapsed >= headers.rows - 1 then
        -- All the rows we've consumed so far have been advanced, start at the
        -- beginning.
        return 1
    end
    -- We've partially advanced, return the correctly computed starting row.
    return headers.rows - rows_elapsed
end

return M