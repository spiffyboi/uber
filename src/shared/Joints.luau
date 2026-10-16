-- Bending a character rig's joints into a pose (sitting, kneeling, an arm
-- out), whichever kind of joint the rig has. Roblox rigs used to be joined
-- with Motor6Ds; rigs made now come with AnimationConstraints instead
-- (confirmed live: a rig from CreateHumanoidModelFromDescription has
-- "LeftHip" as an AnimationConstraint, whose C0 can't be set). Either way
-- the pose here is set on something that's seen by everyone (a Motor6D's
-- C0, or the joint's attachment on the parent part), not on the per-frame
-- Transform an animation would use.

local Joints = {}

-- Turns the joint by `rotation`, about the joint, in the parent part's
-- frame.
function Joints.bendJoint(joint: Instance, rotation: CFrame)
	if joint:IsA("Motor6D") then
		joint.C0 = joint.C0 * rotation
	elseif joint:IsA("AnimationConstraint") then
		local attachment = joint.Attachment0
		if attachment then
			attachment.CFrame = attachment.CFrame * rotation
		end
	end
end

-- Bends each joint named in `bends` ({ [jointName] = rotation }).
function Joints.bend(model: Instance, bends: { [string]: CFrame })
	for _, joint in model:GetDescendants() do
		if bends[joint.Name] and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
			Joints.bendJoint(joint, bends[joint.Name])
		end
	end
end

-- A joint by name (either kind), for setting its Transform frame by frame.
function Joints.find(model: Instance?, name: string): Instance?
	if not model then
		return nil
	end
	for _, joint in model:GetDescendants() do
		if joint.Name == name and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
			return joint
		end
	end
	return nil
end

-- Everything needed to undo bends later: returns a function that puts
-- every joint in `model` back as it is now.
function Joints.snapshot(model: Instance): () -> ()
	local saved = {}
	for _, joint in model:GetDescendants() do
		if joint:IsA("Motor6D") then
			saved[joint] = joint.C0
		elseif joint:IsA("AnimationConstraint") and joint.Attachment0 then
			saved[joint] = joint.Attachment0.CFrame
		end
	end
	return function()
		for joint, cframe in saved do
			if joint.Parent then
				if joint:IsA("Motor6D") then
					joint.C0 = cframe
					joint.Transform = CFrame.new()
				elseif joint:IsA("AnimationConstraint") and joint.Attachment0 then
					joint.Attachment0.CFrame = cframe
					joint.Transform = CFrame.new()
				end
			end
		end
	end
end

return Joints
