-- games/valormortis/theme.lua
-- The menu's look for Valor Mortis: soot black and old parchment, crimson for what is switched on,
-- brass for what is selected. Roles are described in core/ui/widgets.lua.

return {
    subtitle = "VALOR MORTIS",
    mark = "assets/mark.png",   -- the blood handprint, in the mod folder
    panelOpacity = 1.0,
    -- The design's typefaces (assets/fonts, SIL Open Font License), installed into the game's
    -- Content folder by tools/install.ps1. Display: the title and section headings.
    fonts = {
        display = { faces = { Regular = "Cinzel-SemiBold", SemiBold = "Cinzel-SemiBold", Bold = "Cinzel-Bold" } },
        body = { faces = { Regular = "BarlowSemiCondensed-Regular", Medium = "BarlowSemiCondensed-Medium",
            SemiBold = "BarlowSemiCondensed-SemiBold", Bold = "BarlowSemiCondensed-SemiBold" } },
    },
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
