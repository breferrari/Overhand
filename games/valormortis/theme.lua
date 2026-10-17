-- games/valormortis/theme.lua
-- The menu's look for Valor Mortis: soot black and old parchment, crimson for what is switched on,
-- brass for what is selected. Roles are described in core/ui/widgets.lua.

return {
    subtitle = "VALOR MORTIS",
    mark = "assets/mark.png",   -- the blood handprint, in the mod folder
    panelOpacity = 0.97,
    -- The design's fonts, used if the game has them loaded (Misc > Find fonts lists what it has).
    fonts = { display = { "Cinzel" }, body = { "Barlow" } },
    palette = {
        panel = "#14100E",
        edge = "#3A302A",
        corner = "#C9A45C",
        footer = "#110D0B",
        rowSelected = "#1D1714",
        selectionBar = "#C9A45C",
        hairline = "#4A3F37",
        title = "#E6DCC8",
        bright = "#F2EADB",
        label = "#B5AB9A",
        muted = "#8C8273",
        dim = "#6E655A",
        faint = "#5A524A",
        accent = "#B3262D",
        highlight = "#C9A45C",
        toggleOff = "#2A221D",
        descriptionPanel = "#0F0C0A",
        descriptionEdge = "#2A221D",
        chipEdge = "#5A4E44",
        chipText = "#D8CDB8",
        sliderTrack = "#2A221D",
    },
}
