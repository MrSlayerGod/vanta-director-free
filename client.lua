-- Create all services before binding NUI, network events and frame loops.
local context = { state = DirectorClient.newState() }
local modules = {
    "camera",
    "lifecycle",
    "collaboration",
    "placement",
    "history",
    "environment",
    "maths",
    "projects",
    "scene",
    "playback",
    "actions",
    "routes",
    "bridge",
    "input",
    "timeline",
    "shots",
    "capture",
    "models",
    "appearance",
    "recording",
    "groups",
    "attachments",
    "frame",
}
local bindings = {}
for _, name in ipairs(modules) do
    bindings[#bindings + 1] = DirectorClient.modules[name](context)
end
for _, bind in ipairs(bindings) do
    bind()
end
