-- games/valormortis/shared.lua
-- Runtime flags read by more than one Valor Mortis feature.

local Shared = {
    noClipActive = false,
    safeLandingUntil = 0,   -- no fall damage until then (after NoClip / teleport)
}

return Shared
