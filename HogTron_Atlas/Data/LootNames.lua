-- Named drops per boss, NAMES ONLY (no item ids): what each dungeon is known for, so "Where next" can say what a run
-- could give you before you have seen a single drop. Sean 2026-10-05: "yes, names only, labelled".
--
-- SOURCE: the 2004-2006 game (Classic), from memory. NOT VERIFIED ON FOREVER: an item may be gone, renamed, moved
-- to another boss or joined by new ones; the window labels every row "old list". Real drops seen in play (Store)
-- always rank above these. Item ids are never written here (rule since 2026-09-26): an id only enters Atlas when
-- the game hands it over.
--
-- slot = Head Neck Shoulder Back Chest Wrist Hands Waist Legs Feet Ring Trinket Weapon (one-hand) TwoHand OffHand
--        Shield Ranged Wand  -- kind = cloth leather mail plate (armour) | nil (anything else)
local A = HogHealsAtlas
A.Data = A.Data or {}

local function i(name, slot, kind) return { name = name, slot = slot, kind = kind } end

A.Data.LootNames = {
  rfc = {
    ["Oggleflint"] = { i("Chanting Blade", "Weapon") },
    ["Taragaman the Hungerer"] = { i("Cavedweller Bracers", "Wrist", "mail"), i("Crystalline Cuffs", "Wrist", "cloth") },
    ["Jergosh the Invoker"] = { i("Robe of Evocation", "Chest", "cloth"), i("Cursed Felblade", "Weapon") },
  },
  wc = {
    ["Lady Anacondra"] = { i("Serpent's Shoulders", "Shoulder", "leather") },
    ["Lord Cobrahn"] = { i("Robe of the Moccasin", "Chest", "leather"), i("Leggings of the Fang", "Legs", "leather") },
    ["Kresh"] = { i("Kresh's Back", "Shield"), i("Worn Turtle Shell Shield", "Shield") },
    ["Lord Pythas"] = { i("Stinging Viper", "Weapon"), i("Armor of the Fang", "Chest", "leather") },
    ["Skum"] = { i("Tail Spike", "Weapon") },
    ["Lord Serpentis"] = { i("Savage Trodders", "Feet", "mail"), i("Venomstrike", "Ranged"), i("Footpads of the Fang", "Feet", "leather") },
    ["Verdan the Everliving"] = { i("Living Root", "TwoHand"), i("Seedcloud Buckler", "Shield") },
    ["Mutanus the Devourer"] = { i("Deep Fathom Ring", "Ring"), i("Mutant Scale Breastplate", "Chest", "mail"), i("Slime-encrusted Pads", "Shoulder", "leather") },
  },
  vc = {
    ["Rhahk'Zor"] = { i("Rhahk'Zor's Hammer", "TwoHand") },
    ["Sneed's Shredder"] = { i("Buzzer Blade", "Weapon"), i("Taskmaster Axe", "TwoHand") },
    ["Gilnid"] = { i("Lavishly Jeweled Ring", "Ring"), i("Smelting Pants", "Legs", "cloth") },
    ["Mr. Smite"] = { i("Smite's Mighty Hammer", "TwoHand"), i("Thief's Blade", "Weapon"), i("Smite's Reaver", "Weapon") },
    ["Captain Greenskin"] = { i("Emberstone Staff", "TwoHand"), i("Blackened Defias Belt", "Waist", "leather") },
    ["Cookie"] = { i("Cookie's Tenderizer", "Weapon"), i("Cookie's Stirring Rod", "Wand") },
    ["Edwin VanCleef"] = { i("Cruel Barb", "Weapon"), i("Cape of the Brotherhood", "Back"), i("Blackened Defias Armor", "Chest", "leather"), i("Corsair's Overshirt", "Chest", "cloth") },
  },
  sfk = {
    ["Rethilgore"] = { i("Rugged Spaulders", "Shoulder", "leather") },
    ["Razorclaw the Butcher"] = { i("Butcher's Slicer", "Weapon"), i("Butcher's Cleaver", "Weapon"), i("Bloody Apron", "Chest", "cloth") },
    ["Baron Silverlaine"] = { i("Silverlaine's Family Seal", "Ring"), i("Baron's Scepter", "Weapon") },
    ["Commander Springvale"] = { i("Arced War Axe", "TwoHand"), i("Commander's Crest", "Shield") },
    ["Odo the Blindwatcher"] = { i("Girdle of the Blindwatcher", "Waist", "leather"), i("Odo's Ley Staff", "TwoHand") },
    ["Fenrus the Devourer"] = { i("Black Wolf Bracers", "Wrist", "leather"), i("Fenrus' Hide", "Back") },
    ["Wolf Master Nandos"] = { i("Feline Mantle", "Shoulder", "cloth"), i("Wolfmaster Cape", "Back") },
    ["Archmage Arugal"] = { i("Robes of Arugal", "Chest", "cloth"), i("Belt of Arugal", "Waist", "cloth"), i("Meteor Shard", "Weapon") },
  },
  bfd = {
    ["Ghamoo-ra"] = { i("Tortoise Armor", "Chest", "mail"), i("Ghamoo-ra's Bind", "Waist", "cloth") },
    ["Lady Sarevess"] = { i("Naga Battle Gloves", "Hands", "leather"), i("Darkwater Talwar", "Weapon"), i("Naga Heartpiercer", "Ranged") },
    ["Gelihast"] = { i("Algae Fists", "Hands", "mail"), i("Reef Axe", "TwoHand") },
    ["Twilight Lord Kelris"] = { i("Rod of the Sleepwalker", "TwoHand"), i("Gaze Dreamer Pants", "Legs", "cloth") },
    ["Old Serra'kis"] = { i("Glowing Thresher Cape", "Back"), i("Bands of Serra'kis", "Wrist", "leather"), i("Bite of Serra'kis", "Weapon") },
    ["Aku'mai"] = { i("Leech Pants", "Legs", "cloth"), i("Moss Cinch", "Waist", "leather"), i("Strike of the Hydra", "TwoHand") },
  },
  stocks = {
    ["Kam Deepfury"] = { i("Kam's Walking Stick", "TwoHand") },
    ["Dextren Ward"] = { i("Defias Renegade Ring", "Ring") },
    ["Bruegal Ironknuckle"] = { i("Iron Knuckles", "Weapon"), i("Prison Shank", "Weapon"), i("Jimmied Handcuffs", "Wrist", "mail") },
  },
  gnomer = {
    ["Grubbis"] = { i("Charged Gear", "Ring"), i("Grubbis Paws", "Hands", "mail") },
    ["Viscous Fallout"] = { i("Acidic Walkers", "Feet", "cloth"), i("Hydrocane", "TwoHand") },
    ["Electrocutioner 6000"] = { i("Electrocutioner Leg", "Weapon"), i("Electromagnetic Gigaflux Reactivator", "Head", "cloth") },
    ["Crowd Pummeler 9-60"] = { i("Manual Crowd Pummeler", "TwoHand"), i("Gnomebot Operating Boots", "Feet", "mail") },
    ["Mekgineer Thermaplugg"] = { i("Thermaplugg's Central Core", "Shield"), i("Civinad Robes", "Chest", "cloth"), i("Charged Gear", "Ring") },
  },
  rfk = {
    ["Aggem Thorncurse"] = { i("Thornspike", "Weapon"), i("Ferine Leggings", "Legs", "leather") },
    ["Death Speaker Jargba"] = { i("Death Speaker Mantle", "Shoulder", "cloth"), i("Death Speaker Robes", "Chest", "cloth"), i("Death Speaker Scepter", "Wand") },
    ["Overlord Ramtusk"] = { i("Tusken Helm", "Head", "mail"), i("Corpsemaker", "TwoHand") },
    ["Agathelos the Raging"] = { i("Swinetusk Shank", "Weapon") },
    ["Charlga Razorflank"] = { i("Agamaggan's Clutch", "Waist", "leather"), i("Heart of Agamaggan", "Shield"), i("Pronged Reaver", "Weapon") },
  },
  sm_gy = {
    ["Interrogator Vishas"] = { i("Bloody Brass Knuckles", "Weapon"), i("Torturing Poker", "Weapon") },
    ["Bloodmage Thalnos"] = { i("Bloodmage Mantle", "Shoulder", "cloth"), i("Orb of the Forgotten Seer", "OffHand") },
    ["Azshir the Sleepless"] = { i("Blighted Leggings", "Legs", "cloth"), i("Ghostshard Talisman", "Neck") },
    ["Ironspine"] = { i("Ironspine's Fist", "Weapon"), i("Ironspine's Eye", "Ring") },
  },
  sm_lib = {
    ["Houndmaster Loksey"] = { i("Loksey's Training Stick", "TwoHand"), i("Dog Training Gloves", "Hands", "leather") },
    ["Arcanist Doan"] = { i("Hypnotic Blade", "Weapon"), i("Illusionary Rod", "TwoHand"), i("Mantle of Doan", "Shoulder", "cloth"), i("Robe of Doan", "Chest", "cloth") },
  },
  sm_arm = {
    ["Herod"] = { i("Raging Berserker's Helm", "Head", "mail"), i("Ravager", "TwoHand"), i("Herod's Shoulder", "Shoulder", "mail") },
    ["Trash and chests"] = { i("Scarlet Chestpiece", "Chest", "mail"), i("Scarlet Leggings", "Legs", "mail"), i("Scarlet Boots", "Feet", "mail"), i("Scarlet Belt", "Waist", "mail") },
  },
  sm_cath = {
    ["Scarlet Commander Mograine"] = { i("Mograine's Might", "TwoHand"), i("Aegis of the Scarlet Commander", "Shield"), i("Gauntlets of Divinity", "Hands", "mail") },
    ["High Inquisitor Whitemane"] = { i("Whitemane's Chapeau", "Head", "cloth"), i("Hand of Righteousness", "Weapon"), i("Triune Amulet", "Neck") },
  },
  rfd = {
    ["Tuten'kash"] = { i("Arachnid Gloves", "Hands", "cloth"), i("Carapace of Tuten'kash", "Chest", "mail"), i("Silky Spider Cape", "Back") },
    ["Mordresh Fire Eye"] = { i("Deathmage Sash", "Waist", "cloth"), i("Glowing Eye of Mordresh", "Neck"), i("Mordresh's Lifeless Skull", "OffHand") },
    ["Glutton"] = { i("Glutton's Cleaver", "Weapon"), i("Fleshhide Shoulders", "Shoulder", "leather") },
    ["Ragglesnout"] = { i("Savage Boar's Guard", "Shield"), i("Quillward Harness", "Chest", "mail") },
    ["Amnennar the Coldbringer"] = { i("Icemetal Barbute", "Head", "plate"), i("Robes of the Lich", "Chest", "cloth"), i("Deathchill Armor", "Chest", "mail"), i("Coldrage Dagger", "Weapon"), i("Bonefingers", "Hands", "cloth") },
  },
  ulda = {
    ["Revelosh"] = { i("Revelosh's Boots", "Feet", "mail"), i("Revelosh's Gloves", "Hands", "leather"), i("Revelosh's Armguards", "Wrist", "cloth") },
    ["Ironaya"] = { i("Stoneweaver Leggings", "Legs", "cloth"), i("Ironaya's Bracers", "Wrist", "mail"), i("Ironshod Bludgeon", "TwoHand") },
    ["Ancient Stone Keeper"] = { i("Cragfists", "Hands", "mail") },
    ["Galgann Firehammer"] = { i("Galgann's Fireblaster", "Ranged"), i("Galgann's Firehammer", "Weapon"), i("Emberscale Cape", "Back") },
    ["Grimlok"] = { i("Grimlok's Charge", "TwoHand"), i("Grimlok's Tribal Vestments", "Chest", "leather") },
    ["Archaedas"] = { i("Stoneslayer", "TwoHand"), i("The Rockpounder", "TwoHand"), i("Archaedic Stone", "Ring"), i("Spaulders of a Lost Age", "Shoulder", "mail") },
  },
  zf = {
    ["Gahz'rilla"] = { i("Gahz'rilla Scale Cloak", "Back"), i("Gahz'rilla Fang", "Weapon") },
    ["Antu'sul"] = { i("Sang'thraze the Deflector", "Weapon"), i("Vice Grips", "Hands", "mail"), i("Lifeforce Dirk", "Weapon") },
    ["Witch Doctor Zum'rah"] = { i("Jumanza Grips", "Hands", "leather"), i("Zum'rah's Vexing Cane", "TwoHand") },
    ["Nekrum Gordok"] = { i("Diabolic Skiver", "TwoHand"), i("Jinxed Hoodoo Skull", "OffHand"), i("Bad Mojo Mask", "Head", "leather") },
    ["Chief Ukorz Sandscalp"] = { i("Jang'thraze the Protector", "Weapon"), i("Sandstorm Cloak", "Back"), i("Embrace of the Lycan", "Head", "leather"), i("The Chief's Enforcer", "TwoHand"), i("Big Bad Pauldrons", "Shoulder", "plate") },
  },
  mara = {
    ["Noxxion"] = { i("Noxxion's Shackles", "Wrist", "mail"), i("Heart of Noxxion", "Trinket") },
    ["Razorlash"] = { i("Phytoskin Spaulders", "Shoulder", "leather"), i("Brusslehide Leggings", "Legs", "mail"), i("Vinerot Sandals", "Feet", "cloth") },
    ["Lord Vyletongue"] = { i("Satyr's Lash", "Weapon"), i("Satyrmane Sash", "Waist", "cloth") },
    ["Celebras the Cursed"] = { i("Claw of Celebras", "Weapon"), i("Soothsayer's Headdress", "Head", "leather"), i("Grovekeeper's Drape", "Back") },
    ["Landslide"] = { i("Cloud Stone", "OffHand"), i("Helm of the Mountain", "Head", "mail"), i("Rockgrip Gauntlets", "Hands", "mail") },
    ["Tinkerer Gizlock"] = { i("Gizlock's Hypertech Buckler", "Shield"), i("Inventor's Focal Sword", "Weapon"), i("Megashot Rifle", "Ranged") },
    ["Rotgrip"] = { i("Rotgrip Mantle", "Shoulder", "leather"), i("Gatorbite Axe", "TwoHand") },
    ["Princess Theradras"] = { i("Blackstone Ring", "Ring"), i("Charstone Dirk", "Weapon"), i("Elemental Rockridge Leggings", "Legs", "plate"), i("Princess Theradras' Scepter", "Wand"), i("Blade of Eternal Darkness", "Weapon") },
  },
  st = {
    ["Atal'alarion"] = { i("Atal'alarion's Tusk Ring", "Ring"), i("Darkwater Bracers", "Wrist", "mail") },
    ["Weaver"] = { i("Dawnspire Cord", "Waist", "cloth"), i("Drakefang Butcher", "Weapon") },
    ["Dreamscythe"] = { i("Drakeclaw Band", "Ring"), i("Dragonrider Boots", "Feet", "cloth") },
    ["Morphaz"] = { i("Drakestone", "Ring"), i("Nightfall Drape", "Back") },
    ["Hazzas"] = { i("Wingveil Cloak", "Back"), i("Drakefang Butcher", "Weapon") },
    ["Shade of Eranikus"] = { i("Dragon's Call", "Weapon"), i("Dragon's Eye", "Neck"), i("Tooth of Eranikus", "Weapon") },
    ["Avatar of Hakkar"] = { i("Fist of the Damned", "Weapon"), i("Hakkari Shroud", "Back"), i("Embrace of the Wind Serpent", "Chest", "mail"), i("Bloodshot Greaves", "Feet", "mail") },
  },
  brd = {
    ["Lord Roccor"] = { i("Earthslag Shoulders", "Shoulder", "plate") },
    ["Bael'Gar"] = { i("Lavacrest Leggings", "Legs", "plate") },
    ["Lord Incendius"] = { i("Cinderhide Armsplints", "Wrist", "mail"), i("Kindling Stave", "TwoHand") },
    ["Pyromancer Loregrain"] = { i("Flamestrider Robes", "Chest", "cloth"), i("Pyremail Wristguards", "Wrist", "mail") },
    ["Houndmaster Grebmar"] = { i("Houndmaster's Bow", "Ranged"), i("Houndmaster's Rifle", "Ranged") },
    ["Ambassador Flamelash"] = { i("Cape of the Fire Salamander", "Back"), i("Circle of Flame", "Head", "cloth") },
    ["General Angerforge"] = { i("Angerforge's Battle Axe", "TwoHand"), i("Force of Will", "Trinket"), i("Warstrife Leggings", "Legs", "plate") },
    ["Golem Lord Argelmach"] = { i("Golem Skull Helm", "Head", "mail"), i("Rubidium Hammer", "Weapon"), i("Second Wind", "Trinket") },
    ["Hurley Blackbreath"] = { i("Hurley's Tankard", "Weapon"), i("Ragefury Eyepatch", "Head", "leather") },
    ["Phalanx"] = { i("Fists of Phalanx", "Hands", "plate"), i("Bloodfist", "Weapon") },
    ["Plugger Spazzring"] = { i("Barman Shanker", "Weapon") },
    ["Magmus"] = { i("Magmus Stone", "OffHand"), i("Lavastone Hammer", "TwoHand"), i("Magma Forged Band", "Ring") },
    ["Emperor Dagran Thaurissan"] = { i("Hand of Justice", "Trinket"), i("Emperor's Seal", "Ring"), i("Imperial Jewel", "Neck"), i("Ironfoe", "Weapon"), i("Thaurissan's Royal Scepter", "Wand"), i("Dreadforge Retaliator", "TwoHand"), i("Guiding Stave of Wisdom", "TwoHand") },
  },
  lbrs = {
    ["Highlord Omokk"] = { i("Fist of Omokk", "TwoHand"), i("Tressermane Leggings", "Legs", "leather"), i("Ogre Toothpick Shooter", "Ranged") },
    ["Shadow Hunter Vosh'gajin"] = { i("Blackcrow", "Ranged"), i("Kayser's Boots of Precision", "Feet", "leather"), i("Hands of Power", "Hands", "cloth") },
    ["War Master Voone"] = { i("Brazecore Armguards", "Wrist", "mail"), i("Talisman of Evasion", "Trinket") },
    ["Mother Smolderweb"] = { i("Smolderweb's Eye", "Trinket") },
    ["Halycon"] = { i("Slashclaw Bracers", "Wrist", "leather"), i("Pads of the Dread Wolf", "Shoulder", "mail") },
    ["Gizrul the Slavener"] = { i("Wolfshear Leggings", "Legs", "leather") },
    ["Overlord Wyrmthalak"] = { i("Reiver Claws", "Hands", "plate"), i("Trueaim Gauntlets", "Hands", "mail"), i("Chillpike", "TwoHand"), i("Relentless Scythe", "TwoHand"), i("Living Shoulders", "Shoulder", "leather"), i("Wyrmthalak's Shackles", "Wrist", "leather") },
  },
  ubrs = {
    ["Warchief Rend Blackhand"] = { i("Doomhide Gauntlets", "Hands", "leather") },
    ["The Beast"] = { i("Finkle's Skinner", "Weapon"), i("Frostweaver Cape", "Back"), i("Blademaster Leggings", "Legs", "leather") },
    ["General Drakkisath"] = { i("Draconian Deflector", "Shield"), i("Shadow Prowler's Cloak", "Back"), i("Blackblade of Shahram", "Weapon"), i("Crystal Adorned Crown", "Head", "cloth") },
  },
  dm_e = {
    ["Zevrim Thornhoof"] = { i("Felhide Cap", "Head", "leather"), i("Satyr's Bow", "Ranged") },
    ["Lethtendris"] = { i("Lethtendris's Wand", "Wand"), i("Band of Vigor", "Ring") },
    ["Alzzin the Wildshaper"] = { i("Razor Gauntlets", "Hands", "plate"), i("Shadewood Cloak", "Back"), i("Ring of Demonic Guile", "Ring"), i("Whipvine Cord", "Waist", "cloth") },
  },
  dm_w = {
    ["Tendris Warpwood"] = { i("Stoneflower Staff", "TwoHand"), i("Warpwood Binding", "Waist", "mail") },
    ["Illyanna Ravenoak"] = { i("Force Imbued Gauntlets", "Hands", "mail"), i("Padre's Trousers", "Legs", "cloth") },
    ["Magister Kalendris"] = { i("Mindtap Talisman", "Trinket"), i("Elder Magus Pendant", "Neck") },
    ["Immol'thar"] = { i("Vigilance Charm", "Trinket"), i("Eyestalk Cord", "Waist", "cloth"), i("Demon Howl Wristguards", "Wrist", "mail") },
    ["Prince Tortheldrin"] = { i("Mind Carver", "Weapon"), i("Timeworn Mace", "Weapon"), i("Distracting Dagger", "Weapon"), i("Chestplate of Tranquility", "Chest", "plate") },
  },
  dm_n = {
    ["Captain Kromcrush"] = { i("Mugger's Belt", "Waist", "leather"), i("Kromcrush's Chestplate", "Chest", "plate") },
    ["Cho'Rush the Observer"] = { i("Insightful Hood", "Head", "cloth"), i("Mana Channeling Wand", "Wand"), i("Observer's Shield", "Shield") },
    ["King Gordok"] = { i("Gordok's Handguards", "Hands", "plate"), i("Leggings of Destruction", "Legs", "mail"), i("Tooth of Gnarr", "Neck"), i("Bulky Iron Spaulders", "Shoulder", "plate"), i("Gordok Nose Ring", "Ring"), i("Harmonious Gauntlets", "Hands", "cloth") },
  },
  strat_live = {
    ["Timmy the Cruel"] = { i("Timmy's Galoshes", "Feet", "mail"), i("Grimgore Noose", "Waist", "leather"), i("Vambraces of the Sadist", "Wrist", "mail") },
    ["Cannon Master Willey"] = { i("Helm of the Executioner", "Head", "mail"), i("Barrage Girdle", "Waist", "cloth"), i("Willey's Portable Howitzer", "Ranged") },
    ["Archivist Galford"] = { i("Archivist Cape", "Back"), i("Book of the Dead", "OffHand") },
    ["Balnazzar"] = { i("Wand of Biting Cold", "Wand"), i("Demonshear", "TwoHand"), i("Shroud of the Nathrezim", "Back"), i("Crown of Tyranny", "Head", "plate"), i("Gift of the Elven Magi", "Weapon"), i("Hammer of the Grand Crusader", "TwoHand") },
  },
  strat_ud = {
    ["Nerub'enkan"] = { i("Carapace Spine Crossbow", "Ranged"), i("Darkspinner Claws", "Hands", "leather"), i("Chitinous Plate Legguards", "Legs", "plate"), i("Fangdrip Runners", "Feet", "mail") },
    ["Baroness Anastari"] = { i("Banshee Finger", "Wand"), i("Screeching Bow", "Ranged"), i("Shadowy Laced Handwraps", "Hands", "cloth"), i("Anastari Heirloom", "Ring"), i("Banshee's Touch", "Hands", "mail") },
    ["Maleki the Pallid"] = { i("Maleki's Footwraps", "Feet", "cloth"), i("Skull of Burning Shadows", "OffHand"), i("Twig of the World Tree", "Ring") },
    ["Magistrate Barthilas"] = { i("Idol of Brutality", "Trinket"), i("Magistrate's Cuffs", "Wrist", "mail"), i("Crimson Felt Hat", "Head", "cloth") },
    ["Ramstein the Gorger"] = { i("Animated Chain Necklace", "Neck"), i("Band of Flesh", "Ring"), i("Slavedriver's Cane", "TwoHand") },
    ["Baron Rivendare"] = { i("Runeblade of Baron Rivendare", "TwoHand"), i("Bonescraper", "Weapon"), i("Cape of the Black Baron", "Back"), i("Seal of Rivendare", "Ring"), i("Dracorian Gauntlets", "Hands", "plate") },
  },
  scholo = {
    ["Kirtonos the Herald"] = { i("Loomguard Armbraces", "Wrist", "leather"), i("Spellbound Tome", "OffHand"), i("Frightskull Shaft", "TwoHand"), i("Gargoyle Slashers", "Hands", "leather") },
    ["Jandice Barov"] = { i("Phantasmal Cloak", "Back"), i("Royal Cap Spaulders", "Shoulder", "cloth"), i("Wraithplate Leggings", "Legs", "plate"), i("Ghostloom Leggings", "Legs", "leather") },
    ["Rattlegore"] = { i("Bone Ring Helm", "Head", "mail"), i("Rattlecage Buckler", "Shield") },
    ["Marduk Blackpool"] = { i("Ebon Vise", "Hands", "leather"), i("Death Knight Sabatons", "Feet", "mail") },
    ["Ras Frostwhisper"] = { i("Alanna's Embrace", "Chest", "cloth"), i("Freezing Lich Robes", "Chest", "cloth"), i("Maelstrom Leggings", "Legs", "mail"), i("Soulstealer Mantle", "Shoulder", "cloth"), i("Bonechill Hammer", "Weapon") },
    ["Lorekeeper Polkelt"] = { i("Lorekeeper's Ring", "Ring") },
    ["Lord Alexei Barov"] = { i("Deadwalker Mantle", "Shoulder", "leather") },
    ["Darkmaster Gandling"] = { i("Headmaster's Charge", "TwoHand") },
  },
}

--- Named drops for a dungeon as a flat list: { boss, name, slot, kind }. Empty for a dungeon with none.
function A.Data.NamedDrops(dkey)
  local out = {}
  local bosses = A.Data.LootNames[dkey]
  if type(bosses) ~= "table" then return out end
  local names = {}
  for boss in pairs(bosses) do names[#names + 1] = boss end
  table.sort(names)
  for _, boss in ipairs(names) do
    for _, it in ipairs(bosses[boss]) do out[#out + 1] = { boss = boss, name = it.name, slot = it.slot, kind = it.kind } end
  end
  return out
end
