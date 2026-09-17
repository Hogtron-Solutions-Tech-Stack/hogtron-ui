-- Blizzard FrameXML helpers that vendored libraries still call but some clients no longer ship.
-- Loaded FIRST (before embeds.xml). Only ever fills a hole: if the client has the function, it is left alone.
-- These names do not exist in the client's own code when we define them, so nothing secure can call into them.
--
-- SetDesaturation: AceGUI-3.0 CheckBox (v26, the newest there is; retail addons ship the same file) calls it on
-- every checkbox refresh. Missing on the WoW: Forever beta 1.60.1 -> the options window threw on the first tab
-- that contains a toggle ("AceGUIWidget-CheckBox.lua:130: attempt to call a nil value").
if type(SetDesaturation) ~= "function" then
  function SetDesaturation(texture, desaturate)
    if not texture then return end
    local supported = texture.SetDesaturated and texture:SetDesaturated(desaturate and true or false)
    if supported == false and texture.SetVertexColor then
      if desaturate then texture:SetVertexColor(0.5, 0.5, 0.5) else texture:SetVertexColor(1, 1, 1) end
    end
  end
end
