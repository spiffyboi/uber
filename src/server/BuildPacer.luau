-- Building the whole city in one go takes longer than Roblox lets a script
-- run without pausing (confirmed live: "Script timeout: exhausted allowed
-- execution time" part way through the cross-street buildings). Builders
-- call breathe() as they go; it pauses for a frame whenever they've been
-- working flat out for a moment.

local BuildPacer = {}

local lastPause = os.clock()

function BuildPacer.breathe()
	if os.clock() - lastPause > 0.05 then
		task.wait()
		lastPause = os.clock()
	end
end

return BuildPacer
