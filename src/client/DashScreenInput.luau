-- Clicks on the car's dash screen (the GpsUnit's SurfaceGui).
--
-- Roblox's own SurfaceGui input can't reach that screen from the driver's
-- seat: it raycasts from the camera and the first thing it hits is the car's
-- invisible Chassis box, which (by design -- it's the car's whole collision
-- volume) encloses the cabin, the camera and the screen itself. Confirmed
-- live: a click on the Accept button hit Chassis at distance 0.02, then the
-- driver's own legs, and never reached the screen. CanQuery can't be turned
-- off on a part that still collides, so instead this casts against the screen
-- part only and maps the hit onto the SurfaceGui canvas by hand.

local UserInputService = game:GetService("UserInputService")

local DashScreenInput = {}

-- Canvas pixel position under a GUI-inset-relative screen point (what
-- InputObject.Position gives), or nil if the point isn't on the screen's face.
function DashScreenInput.canvasPoint(unit: BasePart, screen: SurfaceGui, screenPos: Vector2): Vector2?
	local camera = workspace.CurrentCamera
	local ray = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { unit }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 50, params)
	if not result then
		return nil
	end

	local size = unit.Size
	local p = unit.CFrame:PointToObjectSpace(result.Position)
	-- The SurfaceGui sits on the Front (-Z) face; any other face is a miss.
	if p.Z > -size.Z / 2 + 0.02 then
		return nil
	end
	-- Seen head-on, the Front face's left edge is the part's local +X side
	-- and its top edge is local +Y.
	local u = (size.X / 2 - p.X) / size.X
	local v = (size.Y / 2 - p.Y) / size.Y
	return Vector2.new(u * screen.AbsoluteSize.X, v * screen.AbsoluteSize.Y)
end

local function isOver(button: GuiObject, point: Vector2): boolean
	local pos, size = button.AbsolutePosition, button.AbsoluteSize
	return point.X >= pos.X and point.X <= pos.X + size.X and point.Y >= pos.Y and point.Y <= pos.Y + size.Y
end

-- Calls `callback` when the player clicks/taps `button` on the dash screen.
-- If Roblox's own input ever does deliver the click to the button (e.g. a
-- future camera angle with nothing in the way), the input arrives here
-- already processed and is skipped, so the button's own MouseButton1Click
-- handles it instead -- callers should guard against double-firing anyway.
function DashScreenInput.onClick(unit: BasePart, screen: SurfaceGui, button: GuiButton, callback: () -> ()): RBXScriptConnection
	return UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if not button.Visible or not button:IsDescendantOf(game) then
			return
		end
		local point = DashScreenInput.canvasPoint(unit, screen, Vector2.new(input.Position.X, input.Position.Y))
		if point and isOver(button, point) then
			callback()
		end
	end)
end

return DashScreenInput
