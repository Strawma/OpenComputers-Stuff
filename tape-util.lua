-- Code shamelessly stolen from https://github.com/RVRX/computronics-tape-util.g

--[[ A Utility Program for Computronics Cassette Tapes.
Provides:
	- automatic tape writing from web location
	- automatic tape looping
	- More in future updates
]]

local args = { ... }

local component = require("component")
local fs = require("filesystem")
local shell = require("shell")
local term = require("term")
local computer = require("computer")

local function getTape()
  if not component.isAvailable("tape_drive") then return nil end
  return component.tape_drive
end

local function helpText()
	print("Usage:")
	print(" - 'tape-util' to display this help text")
	print(" - 'tape-util loop' to loop a cassette tape")
  	print(" - 'tape-util dl [num files] [web dir]' to write web directory to tape")
  	print(" - 'tape-util dl' to display full download utility help text")
  	return
end

local function helpTextDl()
	print("Usage:")
  	print(" - 'tape-util dl' to display this help text")
  	print(" - 'tape-util dl [num files] [web dir]' to write web directory to tape")
  	print("directory url must contain ending forward-slash.\nFiles must be named their order number .dfpwm, ex:\n'1.dfpwm', '2.dfpwm', etc")
end

--add helpText for loop util, when more features are added.





--TAPE LOOP CONTENT------------
--Program for looping tracks

local tape = getTape()
if not tape then
-- 	print("This program requires a tape drive to run.")
-- 	return
end

--Returns true if position 1 away is zero
local function seekNCheck()
	--seek 1 and check
	tape.seek(1)
	print("Seeking 1...")
	local b = tape.read(1)
	if not b or b == "\0" then
		return true
	else return false
	end
end

--Checks multiple bits into distance to make sure it is actual end of track, and not just a quiet(?) part
local function seekNCheckMultiple()
	for i=1,10 do
		if seekNCheck() == false then
			return false
		end
	end
	return true
end
	
-- this could be made into a more efficient algo?
local function findTapeEnd( ... )

	local accuracy = 100
	print("Using accuracy of " .. accuracy)

	local tapeSize = tape.getSize()
	print("Tape has size of: " .. tapeSize)
	tape.seek(-tape.getPosition()) -- rewind tape
	local runningEnd = 0

	for i=0,tapeSize do --for every piece of the tape
	
		--os.queueEvent("randomEvent") -- timeout
		--os.pullEvent()				 -- prevention
		computer.pullSignal(0)


		tape.seek(accuracy) --seek forward one unit (One takes too long, bigger values not as accurate)
		local b = tape.read(1)
		if b and b ~= 0 then --if current location is not a zero
			runningEnd = i*accuracy --Update Running runningEnd var. i * accuracy gets current location in tape
			print("End Candidate: " .. runningEnd)
		elseif seekNCheckMultiple() then --check a few spots away to see if zero as well
			return runningEnd
		--else return runningEnd --otherwise, (if 0) return runningEnd
		end --end if
	end

end

--Main Function
local function looper( ... )
	print("Initializing...")
	--find tape end
	print("Locating end of song...")
	local endLoc = findTapeEnd()
	print("End of song at position " .. endLoc .. ", or " .. endLoc/6000 .. " seconds in\n")

	print("Starting Loop! Hold Ctrl+T to Terminate")
	while true do
		tape.seek(-tape.getPosition())
		tape.play()
		print("... Playing")
		os.sleep(endLoc/6000)
		print("Song Ended, Restarting...")
	end

	--play tape until 
end

--END TAPE LOOP CONTENT---------------------------------





--START TAPE DL CONTENT--------------------------------
--Credit to the writers of Computronics for the bulk of wrtieTapeModified() function, see README for more info.
local function writeTapeModified(relPath)
  local tape = getTape()
  if not tape then
    print("This program requires a tape drive to run.")
    return
  end

  local block = 8192
  tape.stop()

  local path = shell.resolve(relPath)
  local filesize = fs.size(path)
  if not filesize then
    io.stderr:write("file not found: " .. path .. "\n")
    return
  end

  local file, msg = io.open(path, "rb")
  if not file then
    io.stderr:write("Failed to open file " .. relPath .. ": " .. tostring(msg) .. "\n")
    return
  end

  print("Writing...")
  local _, y = term.getCursor()

  if filesize > tape.getSize() then
    term.setCursor(1, y)
    io.stderr:write("Error: File is too large for tape, shortening file\n")
    _, y = term.getCursor()
    filesize = tape.getSize()
  end

  local written = 0
  while written < filesize do
    local chunk = file:read(math.min(block, filesize - written))
    if not chunk or #chunk == 0 then break end

    if not tape.isReady() then
      io.stderr:write("\nError: Tape was removed during writing.\n")
      file:close()
      return
    end

    tape.write(chunk)
    written = written + #chunk

    term.setCursor(1, y)
    term.write("Read " .. written .. " of " .. filesize .. " bytes...")
    os.sleep(0)
  end

  file:close()
  tape.stop()
  print("\nDone.")
end

local function tapeDl(numParts, url)
  local tape = getTape()
  if not tape then
    print("This program requires a tape drive to run.")
    return
  end

  local i = 1
  while i <= tonumber(numParts) do
    shell.execute('wget -f "' .. url .. i .. '.dfpwm" "/tmp/temp_dl.dfpwm"')
    writeTapeModified("/tmp/temp_dl.dfpwm")
    fs.remove("/tmp/temp_dl.dfpwm")
    i = i + 1
  end

  tape.seek(-tape.getPosition()) -- see note below
end
--END TAPE DL CONTENT----------------------------------






if args[1] == "loop" then
	looper()
elseif args[1] == "dl" then
	if args[2] ~= nil then
		print("running tapeDl")
		tapeDl(args[2],args[3])
	else helpTextDl()
	end
else
	helpText()
end


--[[ known issues:
tape-util dl, does not rewind at start.
tape-util dl, should say when it rewinds at end, that the program is finished.
findTapeEnd, timeout protection might not be necessary anymore, adding bloat.
looper(), could do with some cleaner prints. can screen be cleared?
looper(), needs accuracy argument! will be very slow on larger cassettes to find length

]]
