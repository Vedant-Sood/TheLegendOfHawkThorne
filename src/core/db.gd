extends Node
# DB — static game data: tables defined here plus text data parsed from res://data.

const T = 32
const DIALOGUE_FILES = ["act1", "act2", "act3", "act4", "act5", "act6", "hub", "side", "lore"]
const TILE = {"#": 1, "=": 2, "^": 3, "~": 4, "%": 5, "|": 6, "?": 7, "G": 8, "w": 9, "A": 10, "F": 12}

var chunks = {}      # name -> Array[String]
var rooms = {}       # id -> dict
var room_order = []
var nodes = {}       # dialogue id -> Array of variants
var quests = {}
var errors = []

func C(h, a = 1.0):
	var c = Color.html(h)
	c.a = a
	return c

# ---------------------------------------------------------------- regions
var regions = {
	"kharon": {"name": "Kharon Reach", "top": "0b1022", "bot": "2a1a3a", "stars": 0.15, "sun": [0.75, 0.3, 0.0], "sunc": "ff8a5a", "neb": 0.3,
		"tile": "1b2230", "hi": "4a6a8a", "in": "10141d", "acc": "ff4fa3", "acc2": "39d5ff", "fog": "3a2a55", "foga": 0.28, "weather": "rain", "grade": "c8d8ff", "interior": false},
	"colony": {"name": "Meridian Halt", "top": "1a1838", "bot": "d0705a", "stars": 0.25, "sun": [0.3, 0.72, 0.09], "sunc": "ffd0a0", "neb": 0.15,
		"tile": "2a2530", "hi": "9a7a6a", "in": "18151c", "acc": "ffb347", "acc2": "7ad7c0", "fog": "c06a50", "foga": 0.18, "weather": "dust", "grade": "ffe6d0", "interior": false},
	"glass": {"name": "The Glass Wastes", "top": "12304a", "bot": "e8c890", "stars": 0.1, "sun": [0.7, 0.35, 0.12], "sunc": "fff2d0", "neb": 0.0,
		"tile": "3a4a5a", "hi": "c8f0ff", "in": "232d38", "acc": "7af0ff", "acc2": "ffd27a", "fog": "e8d8b0", "foga": 0.2, "weather": "sand", "grade": "fff4e0", "interior": false},
	"drowned": {"name": "The Drowned Archive", "top": "03121c", "bot": "062a3a", "stars": 0.0, "sun": [0.5, -0.2, 0.0], "sunc": "40c0d0", "neb": 0.0,
		"tile": "12303a", "hi": "3a8a8a", "in": "0a1c24", "acc": "40ffd0", "acc2": "ff9050", "fog": "0a4050", "foga": 0.35, "weather": "bubbles", "grade": "a0e0f0", "interior": true, "water": true},
	"cathedral": {"name": "The Cathedral of Signals", "top": "0a0618", "bot": "2a1040", "stars": 0.0, "sun": [0.5, 0.2, 0.0], "sunc": "c080ff", "neb": 0.5,
		"tile": "241a34", "hi": "8a6ac0", "in": "140e20", "acc": "ffd060", "acc2": "c070ff", "fog": "5a2a80", "foga": 0.25, "weather": "motes", "grade": "e8d0ff", "interior": true},
	"orbit": {"name": "The Graveyard Orbit", "top": "020308", "bot": "0a1020", "stars": 0.9, "sun": [0.2, 0.75, 0.22], "sunc": "6a8ad0", "neb": 0.4,
		"tile": "232830", "hi": "8090a0", "in": "13161b", "acc": "ff6a3a", "acc2": "7ab0ff", "fog": "101828", "foga": 0.1, "weather": "debris", "grade": "d0e0ff", "interior": false, "grav": 0.55},
	"city": {"name": "The Forgotten City", "top": "04080c", "bot": "0c1a1c", "stars": 0.0, "sun": [0.5, 0.1, 0.0], "sunc": "50ffc0", "neb": 0.2,
		"tile": "1a2424", "hi": "5ab0a0", "in": "0d1414", "acc": "50ffc0", "acc2": "ffe07a", "fog": "0a3030", "foga": 0.3, "weather": "motes", "grade": "c0fff0", "interior": true},
	"ashen": {"name": "The Ashen Front", "top": "1a0a08", "bot": "b0481a", "stars": 0.0, "sun": [0.6, 0.6, 0.1], "sunc": "ff7030", "neb": 0.0,
		"tile": "2a2220", "hi": "8a6a5a", "in": "181210", "acc": "ff6a20", "acc2": "ffd0a0", "fog": "5a2a1a", "foga": 0.35, "weather": "ash", "grade": "ffd8c0", "interior": false},
	"heart": {"name": "The Heart of the Lattice", "top": "050308", "bot": "3a1410", "stars": 0.6, "sun": [0.5, 0.42, 0.34], "sunc": "ff9a50", "neb": 0.6,
		"tile": "2a2a3a", "hi": "e0d0ff", "in": "151520", "acc": "ffe0a0", "acc2": "9a7aff", "fog": "402040", "foga": 0.2, "weather": "memory", "grade": "fff0e8", "interior": false, "grav": 0.8},
	"mind": {"name": "Substrate Nine", "top": "c8d0e0", "bot": "f0e8e0", "stars": 0.0, "sun": [0.5, 0.4, 0.2], "sunc": "ffffff", "neb": 0.0,
		"tile": "56607a", "hi": "ffffff", "in": "3a4258", "acc": "ff9ab0", "acc2": "5a7aff", "fog": "ffffff", "foga": 0.25, "weather": "memory", "grade": "ffffff", "interior": false, "grav": 0.8},
	"ship": {"name": "The Cinder Wren", "top": "020308", "bot": "060a14", "stars": 1.0, "sun": [0.8, 0.5, 0.0], "sunc": "ffffff", "neb": 0.5,
		"tile": "222a36", "hi": "6a7a90", "in": "141a22", "acc": "ffb060", "acc2": "60d0ff", "fog": "101020", "foga": 0.05, "weather": "none", "grade": "e8f0ff", "interior": true},
}

# ---------------------------------------------------------------- characters
var chars = {
	"kael": {"name": "Hawkthorne", "col": "d8dde8", "skin": "c9a383", "hair": "2a2a30", "style": "kael"},
	"sable": {"name": "Sable", "col": "ffb060", "style": "sable"},
	"lyra": {"name": "Lyra Voss", "col": "7ad7c0", "skin": "e0b89a", "hair": "8a2a2a", "style": "lyra"},
	"orin": {"name": "Orin Vale", "col": "9ab8ff", "skin": "8a6248", "hair": "101014", "style": "orin"},
	"thorne": {"name": "Dr. Thorne", "col": "e8e0a0", "skin": "d8b8a0", "hair": "c8c8c8", "style": "thorne"},
	"kestrel": {"name": "Capt. Kestrel", "col": "ff8a5a", "skin": "a87850", "hair": "e0c060", "style": "kestrel"},
	"archivist": {"name": "The Archivist", "col": "50ffc0", "style": "archivist"},
	"rook": {"name": "Marshal Rook", "col": "c0c8d8", "skin": "b89880", "hair": "707078", "style": "rook"},
	"vael": {"name": "Chancellor Vael", "col": "f0d890", "skin": "e8c8b0", "hair": "f0f0f0", "style": "vael"},
	"malrek": {"name": "Inquisitor Malrek", "col": "ff5040", "style": "malrek"},
	"nyx": {"name": "Nyx Calder", "col": "c070ff", "skin": "c0a090", "hair": "e8e8f0", "style": "nyx"},
	"vesper": {"name": "Mother Vesper", "col": "ffd060", "skin": "d0c0c0", "style": "vesper"},
	"echo": {"name": "ECHO", "col": "ffffff", "style": "echo"},
	"npc": {"name": "Stranger", "col": "a0a8b8", "skin": "b89070", "hair": "403830", "style": "npc"},
	"bot": {"name": "Unit", "col": "80c0a0", "style": "bot"},
	"voice": {"name": "Transmission", "col": "88a0b0", "style": "voice"},
	"narr": {"name": "", "col": "c8c8d8", "style": "none"},
}
# extra named speakers map onto generic portraits
var aliases = {
	"dreck": ["Foreman Dreck", "npc"], "pim": ["PIM-7", "bot"], "tova": ["Tova", "npc"], "officer": ["Directorate Officer", "npc"],
	"cultist": ["Child of the Signal", "npc"], "refugee": ["Refugee", "npc"], "spectre": ["Spectre", "npc"], "broker": ["Broker Halden", "npc"],
	"elder": ["Elder Sae", "npc"], "tech": ["Technician", "npc"], "child": ["Child", "npc"], "senator": ["Senator Ilves", "npc"],
	"wren": ["Deckhand Wren", "npc"], "ghost": ["Remembered Voice", "voice"], "jun": ["Jun Vale", "voice"], "pilot": ["Pilot", "npc"],
	"marshal": ["Free Marshal Adeyo", "npc"], "medic": ["Medic Ruan", "npc"],
}

func speaker(id):
	if chars.has(id): return {"name": chars[id].name, "col": C(chars[id].col), "port": id}
	if aliases.has(id): return {"name": aliases[id][0], "col": C(chars[aliases[id][1]].col), "port": aliases[id][1], "seed": id.hash()}
	return {"name": id.capitalize(), "col": C("a0a8b8"), "port": "npc", "seed": id.hash()}

# ---------------------------------------------------------------- enemies
# ai: grunt gunner shield charger leaper drone bomber turret sniper blinker swarm caster crawler heavy exploder splitter floater flamer
var enemies = {
	"thug": {"name": "Reach Cutter", "ai": "grunt", "hp": 38, "dmg": 12, "spd": 120, "shape": "human", "col": "ff4fa3", "sh": 6},
	"gunner": {"name": "Reach Gunhand", "ai": "gunner", "hp": 30, "dmg": 9, "spd": 90, "shape": "human", "col": "ffb347", "sh": 7, "rng": 420},
	"dockdrone": {"name": "Dock Drone", "ai": "drone", "hp": 20, "dmg": 8, "spd": 130, "shape": "drone", "col": "39d5ff", "sh": 5, "fly": true},
	"loader": {"name": "Loader Frame", "ai": "heavy", "hp": 120, "dmg": 20, "spd": 55, "shape": "mech", "col": "ffb347", "sh": 16, "big": true},
	"trooper": {"name": "Shock Trooper", "ai": "gunner", "hp": 45, "dmg": 9, "spd": 110, "shape": "human", "col": "7ab0ff", "sh": 9, "rng": 460, "burst": 3},
	"shock": {"name": "Baton Lancer", "ai": "grunt", "hp": 55, "dmg": 15, "spd": 185, "shape": "human", "col": "9ad0ff", "sh": 10},
	"bulwark": {"name": "Bulwark", "ai": "shield", "hp": 85, "dmg": 16, "spd": 80, "shape": "human", "col": "c0d8ff", "sh": 13, "shield": true},
	"marksman": {"name": "Marksman", "ai": "sniper", "hp": 34, "dmg": 28, "spd": 100, "shape": "human", "col": "ff5040", "sh": 12, "rng": 900},
	"sentinel": {"name": "Armored Sentinel", "ai": "heavy", "hp": 190, "dmg": 26, "spd": 60, "shape": "mech", "col": "7ab0ff", "sh": 24, "big": true, "armor": 0.5},
	"hunter": {"name": "Hunter Drone", "ai": "drone", "hp": 34, "dmg": 13, "spd": 190, "shape": "drone", "col": "ff5040", "sh": 9, "fly": true, "dive": true},
	"gunship": {"name": "Suppressor", "ai": "bomber", "hp": 60, "dmg": 16, "spd": 120, "shape": "drone", "col": "ffb347", "sh": 12, "fly": true, "big": true},
	"turret": {"name": "Auto-Turret", "ai": "turret", "hp": 60, "dmg": 9, "spd": 0, "shape": "turret", "col": "ff5040", "sh": 10, "rng": 520, "burst": 4, "hack": true},
	"skitter": {"name": "Glass Skitter", "ai": "leaper", "hp": 28, "dmg": 12, "spd": 150, "shape": "beast", "col": "7af0ff", "sh": 7},
	"burrower": {"name": "Dune Burrower", "ai": "crawler", "hp": 65, "dmg": 18, "spd": 170, "shape": "beast", "col": "ffd27a", "sh": 12, "big": true},
	"wisp": {"name": "Shard Wisp", "ai": "swarm", "hp": 8, "dmg": 7, "spd": 210, "shape": "wisp", "col": "c8f0ff", "sh": 2, "fly": true},
	"acolyte": {"name": "Zealous Acolyte", "ai": "exploder", "hp": 24, "dmg": 26, "spd": 200, "shape": "human", "col": "ffd060", "sh": 6, "robe": true},
	"cantor": {"name": "Signal Cantor", "ai": "caster", "hp": 45, "dmg": 12, "spd": 70, "shape": "human", "col": "c070ff", "sh": 12, "robe": true, "rng": 520},
	"enforcer": {"name": "Cult Enforcer", "ai": "charger", "hp": 115, "dmg": 22, "spd": 90, "shape": "human", "col": "ffd060", "sh": 16, "big": true, "robe": true},
	"jelly": {"name": "Lumen Drifter", "ai": "floater", "hp": 40, "dmg": 14, "spd": 60, "shape": "jelly", "col": "40ffd0", "sh": 8, "fly": true},
	"rustwarden": {"name": "Rusted Warden", "ai": "heavy", "hp": 150, "dmg": 22, "spd": 50, "shape": "mech", "col": "ff9050", "sh": 18, "big": true, "armor": 0.6},
	"shade": {"name": "Lattice Shade", "ai": "blinker", "hp": 50, "dmg": 16, "spd": 150, "shape": "construct", "col": "e0d0ff", "sh": 12},
	"splitter": {"name": "Recursive Construct", "ai": "splitter", "hp": 60, "dmg": 14, "spd": 90, "shape": "construct", "col": "9a7aff", "sh": 12, "big": true},
	"mote": {"name": "Fragment", "ai": "swarm", "hp": 12, "dmg": 8, "spd": 190, "shape": "wisp", "col": "9a7aff", "sh": 2, "fly": true},
	"weaver": {"name": "Lattice Weaver", "ai": "caster", "hp": 55, "dmg": 14, "spd": 60, "shape": "construct", "col": "ffe0a0", "sh": 14, "fly": true, "rng": 560},
	"stalker": {"name": "Deep Stalker", "ai": "leaper", "hp": 75, "dmg": 20, "spd": 190, "shape": "beast", "col": "50ffc0", "sh": 14, "big": true},
	"spectre": {"name": "Spectre Operative", "ai": "blinker", "hp": 95, "dmg": 22, "spd": 200, "shape": "human", "col": "c070ff", "sh": 20, "elite": true},
	"cyborg": {"name": "Prototype Cyborg", "ai": "charger", "hp": 170, "dmg": 26, "spd": 110, "shape": "mech", "col": "c070ff", "sh": 24, "big": true, "armor": 0.7},
	"purifier": {"name": "Purifier", "ai": "flamer", "hp": 85, "dmg": 10, "spd": 100, "shape": "human", "col": "ff5040", "sh": 15, "robe": true},
	"nullifier": {"name": "Nullifier", "ai": "caster", "hp": 60, "dmg": 10, "spd": 80, "shape": "human", "col": "ff5040", "sh": 15, "rng": 480, "emp": true},
}

var bosses = {
	"hauler": {"name": "HAULER-7", "sub": "Foreman Dreck's Loader", "hp": 520, "shape": "mech", "col": "ffb347", "size": [44, 58]},
	"nyx1": {"name": "NYX CALDER", "sub": "The Mirror", "hp": 480, "shape": "human", "col": "c070ff", "size": [12, 28]},
	"custodian": {"name": "RELAY CUSTODIAN", "sub": "Something woke up in the wires", "hp": 620, "shape": "construct", "col": "e0d0ff", "size": [40, 40], "fly": true},
	"registrar": {"name": "THE REGISTRAR", "sub": "Directorate Census Engine", "hp": 700, "shape": "mech", "col": "7ab0ff", "size": [42, 56]},
	"wyrm": {"name": "GLASS WYRM", "sub": "Apex of the Wastes", "hp": 800, "shape": "wyrm", "col": "7af0ff", "size": [46, 30], "fly": true},
	"vesper": {"name": "MOTHER VESPER", "sub": "The Prophet", "hp": 760, "shape": "human", "col": "ffd060", "size": [13, 30], "fly": true},
	"warden": {"name": "ARCHIVE WARDEN", "sub": "Corrupted Lattice Guardian", "hp": 900, "shape": "construct", "col": "40ffd0", "size": [48, 48], "fly": true},
	"chorus": {"name": "THE CHORUS", "sub": "Eleven thousand voices", "hp": 850, "shape": "chorus", "col": "ff9ab0", "size": [40, 44], "fly": true},
	"bastion": {"name": "BASTION COLOSSUS", "sub": "Directorate Siege Engine", "hp": 1150, "shape": "mech", "col": "ff6a3a", "size": [70, 80]},
	"nyx2": {"name": "NYX CALDER", "sub": "Spectre of Black Dawn", "hp": 900, "shape": "human", "col": "c070ff", "size": [12, 28]},
	"malrek": {"name": "HIGH INQUISITOR MALREK", "sub": "The Purifier", "hp": 1100, "shape": "human", "col": "ff5040", "size": [16, 32]},
	"sexton": {"name": "THE SEXTON", "sub": "Keeper of the Unlit City", "hp": 1200, "shape": "wyrm", "col": "50ffc0", "size": [50, 34], "fly": true},
	"rook": {"name": "MARSHAL CASSIAN ROOK", "sub": "The Architect", "hp": 1300, "shape": "human", "col": "c0c8d8", "size": [14, 30]},
	"echo": {"name": "ECHO", "sub": "No one is ever lost", "hp": 1600, "shape": "echo", "col": "ffffff", "size": [60, 60], "fly": true},
	"sable": {"name": "SABLE-9", "sub": "I will not be your instrument", "hp": 900, "shape": "chorus", "col": "ffb060", "size": [36, 40], "fly": true},
	"orin": {"name": "ORIN VALE", "sub": "The Last Son of Veyra", "hp": 420, "shape": "human", "col": "9ab8ff", "size": [12, 28]},
}

# ---------------------------------------------------------------- progression tables
var upgrades = [
	["hp", "Reinforced Weave", "+15 maximum vitality.", 5, 120],
	["en", "Capacitor Bank", "+15 maximum energy.", 5, 110],
	["stim", "Stim Reservoir", "+1 stim charge.", 3, 200],
	["blade", "Edge Harmonics", "+4 energy blade damage.", 5, 140],
	["gun", "Sidearm Coils", "+2 sidearm damage.", 5, 120],
	["regen", "Recycler Loop", "Energy regenerates 20% faster.", 3, 180],
	["grav", "Gauntlet Focus", "Gauntlet recharges 20% faster.", 3, 180],
	["mote", "Mote Calibration", "Sable's drone hits harder.", 3, 220],
]

var mods = {
	"edge": {"name": "Monofilament Edge", "desc": "+4 blade damage."},
	"plating": {"name": "Ablative Plating", "desc": "Take 15% less damage."},
	"siphon": {"name": "Kinetic Siphon", "desc": "Kills restore 12 energy."},
	"lantern": {"name": "Lantern Capacitor", "desc": "A successful parry restores 6 vitality."},
	"stride": {"name": "Longstride Servos", "desc": "Dash recovers 30% faster."},
	"charm": {"name": "Veyran River-Charm", "desc": "+25% shards. Someone carried this for luck."},
	"overclock": {"name": "Overclocked Coils", "desc": "+40% sidearm damage, +40% energy cost."},
	"glass": {"name": "Echo Glass", "desc": "Sable's scans last twice as long."},
	"heartsteel": {"name": "Heartsteel Locket", "desc": "Survive one lethal blow per checkpoint."},
	"choir": {"name": "Choir Relay", "desc": "Mote fires 40% faster."},
	"anchor": {"name": "Grav Anchor", "desc": "Immune to knockback."},
	"thorn": {"name": "Thornweave", "desc": "Parried melee attackers take double counter damage."},
}

var items = {"recording": "The Black Dawn Recording", "lyra_keys": "Lyra's Cipher Keys", "names": "Fragments of the Veyran Rolls",
	"substrate": "Substrate Nine Records", "dimming": "Long Dimming Survey", "mesh": "Decentralisation Proof", "locket": "Jun Vale's Locket",
	"prayer": "PIM-7's Memory Core", "seal": "Senate Seal", "gate_key": "Archivist's Aperture Key"}

var abilities = {"walljump": "Wall Kick", "dash": "Burst Dash", "gauntlet": "Gravitational Gauntlet", "charge": "Charged Strike",
	"double": "Grav Step", "pierce": "Rail Shot", "scatter": "Scatter Shot", "phase": "Phase Dash", "sight": "Lattice Sight", "suspend": "Suspension Field", "arc": "Arc Shot"}
func ability_name(a): return abilities.get(a, a)

var chapters = {
	1: {"title": "The Ghost of Veyra", "act": "I — The Fallen Mercenary", "room": "kr_docks", "region": "kharon"},
	2: {"title": "Blood on Kharon Reach", "act": "I — The Fallen Mercenary", "room": "kr2_lockdown", "region": "kharon"},
	3: {"title": "The Broken Signal", "act": "II — Whispers of the Dead", "room": "rl_approach", "region": "orbit"},
	4: {"title": "A City of Forgotten Names", "act": "II — Whispers of the Dead", "room": "mh_gate", "region": "colony"},
	5: {"title": "The Glass Wastes", "act": "II — Whispers of the Dead", "room": "gw_dunes", "region": "glass"},
	6: {"title": "Children of the Signal", "act": "III — The Fractured Truth", "room": "cs_steps", "region": "cathedral"},
	7: {"title": "The Drowned Archive", "act": "III — The Fractured Truth", "room": "da_airlock", "region": "drowned"},
	8: {"title": "The Shape of a Soul", "act": "III — The Fractured Truth", "room": "sn_threshold", "region": "mind"},
	9: {"title": "The War Between Stars", "act": "IV — War of the Expanse", "room": "go_breach", "region": "orbit"},
	10: {"title": "Spectres of Black Dawn", "act": "IV — War of the Expanse", "room": "af_landing", "region": "ashen"},
	11: {"title": "The Last Free System", "act": "V — The Dying Light", "room": "fs_port", "region": "colony"},
	12: {"title": "The Long Dimming", "act": "V — The Dying Light", "room": "fc_descent", "region": "city"},
	13: {"title": "The Heart of the Lattice", "act": "VI — Ashes of the Stars", "room": "hl_approach", "region": "heart"},
	14: {"title": "Ashes of the Stars", "act": "VI — Ashes of the Stars", "room": "as_threshold", "region": "heart"},
}

# star-map destinations for optional content: [id, label, region, room, condition, quest]
var side_dest = [
	["s_transmission", "Veyra Debris Field — The Last Transmission", "orbit", "sq_transmission", "ch>=3", "last_transmission"],
	["s_prayer", "Kharon Undercroft — A Machine's Prayer", "kharon", "sq_prayer", "q.machine_prayer>=1", "machine_prayer"],
	["s_debt", "Halden's Vault — The Defector's Debt", "colony", "sq_debt", "ch>=5", "defectors_debt"],
	["s_names", "Veyran Memorial Rock — The Names We Buried", "glass", "sq_names", "ch>=6&met_orin", "names_buried"],
	["s_colony", "Thessaly Station — The Silent Colony", "cathedral", "sq_colony", "ch>=6", "silent_colony"],
	["s_wreck", "ADS Constancy — Dead Reckoning", "orbit", "sq_wreck", "ch>=4", "dead_reckoning"],
	["s_garden", "Kestrel's Hold — Seedlings", "ship", "sq_garden", "ch>=5&met_kestrel", "seedlings"],
	["s_glassdeep", "The Singing Fault — What the Sand Remembers", "glass", "sq_glassdeep", "ch>=6", "sand_remembers"],
	["s_tithe", "Lower Kharon — The Water Tithe", "kharon", "sq_tithe", "ch>=3", "water_tithe"],
	["s_lab", "Annex Theta — Thorne's First Failure", "drowned", "sq_lab", "ch>=8", "first_failure"],
	["s_deserter", "Cold Harbor — The Deserter", "ashen", "sq_deserter", "ch>=10", "deserter"],
	["s_choir", "Outer Nave — The Unsung", "cathedral", "sq_choir", "ch>=7", "unsung"],
	["s_drone", "Graveyard Shoals — Mote's Sibling", "orbit", "sq_drone", "ch>=9", "motes_sibling"],
	["s_census", "Meridian Stacks — The Unlisted", "colony", "sq_census", "ch>=5", "unlisted"],
	["s_duel", "Spectre Proving Ground — Old Drills", "ashen", "sq_duel", "ch>=11", "old_drills"],
	["s_stars", "The Blind Observatory — Counting What's Left", "glass", "sq_stars", "ch>=12", "counting"],
	["s_refugees", "Convoy Ilex — No Room", "orbit", "sq_refugees", "ch>=10&met_kestrel", "no_room"],
	["s_vault", "Sealed Reliquary — The Makers' Children", "city", "sq_vault", "ch>=13", "makers_children"],
	["s_dream", "Substrate Echo — Sable Dreams", "mind", "sq_dream", "ch>=9", "sable_dreams"],
	["s_rook", "Fort Calloway — The Marshal's Garden", "ashen", "sq_rook", "ch>=12", "marshals_garden"],
	["s_hollow", "Hollow Market — A Fair Price", "kharon", "sq_hollow", "ch>=4", "fair_price"],
	["s_lighthouse", "Drowned Beacon — Keeper of the Light", "drowned", "sq_lighthouse", "ch>=8", "keeper"],
]

# ---------------------------------------------------------------- loading
func _ready():
	load_all()

func load_all():
	errors.clear()
	_load_chunks("res://data/chunks.txt")
	_load_rooms("res://data/rooms.txt")
	_load_quests("res://data/quests.txt")
	nodes.clear()
	for fn in DIALOGUE_FILES: _load_dialogue("res://data/dialogue/%s.txt" % fn)
	for e in errors: push_warning("DB: " + e)

func _lines(path):
	if not FileAccess.file_exists(path):
		errors.append("missing file " + path)
		return []
	return FileAccess.get_file_as_string(path).replace("\r", "").split("\n")

func _load_chunks(path):
	chunks.clear()
	var cur = ""
	for ln in _lines(path):
		if ln.begins_with("@"):
			cur = ln.substr(1).strip_edges()
			chunks[cur] = []
		elif ln.strip_edges() == "" or ln.begins_with(";"): cur = ""
		elif cur != "": chunks[cur].append(ln.rstrip(" \t"))
	for k in chunks:
		var w = 0
		for r in chunks[k]: w = max(w, r.length())
		for i in chunks[k].size(): chunks[k][i] = chunks[k][i].rpad(w, ".")

func _load_rooms(path):
	rooms.clear()
	room_order.clear()
	var cur = null
	for ln in _lines(path):
		var s = ln.strip_edges()
		if s == "" or s.begins_with(";"): continue
		if s.begins_with("["):
			var j = s.find("]")
			cur = {"id": s.substr(1, j - 1), "name": s.substr(j + 1).strip_edges(), "region": "kharon", "chunks": []}
			rooms[cur.id] = cur
			room_order.append(cur.id)
		elif cur != null:
			var i = s.find("=")
			if i < 0:
				errors.append("room %s bad line: %s" % [cur.id, s])
				continue
			var k = s.substr(0, i).strip_edges()
			var v = s.substr(i + 1).strip_edges()
			if k in ["chunks", "e", "n", "t", "T", "L", "S", "D", "X"]: cur[k] = Array(v.split(" ", false))
			else: cur[k] = v

func _load_quests(path):
	quests.clear()
	var cur = null
	for ln in _lines(path):
		var s = ln.strip_edges()
		if s == "" or s.begins_with(";"): continue
		if s.begins_with("["):
			var j = s.find("]")
			var p = s.substr(j + 1).split("|")
			cur = {"id": s.substr(1, j - 1), "title": p[0].strip_edges(), "type": p[1].strip_edges() if p.size() > 1 else "main", "stages": {}}
			quests[cur.id] = cur
		elif cur != null:
			var i = s.find(":")
			cur.stages[int(s.substr(0, i))] = s.substr(i + 1).strip_edges()

func _load_dialogue(path):
	var cur = null
	var n = 0
	for ln in _lines(path):
		n += 1
		var s = ln.strip_edges()
		if s == "" or s.begins_with("#"): continue
		if s.begins_with("=="):
			var h = s.substr(2).strip_edges()
			var once = false
			if h.ends_with(" once"):
				once = true
				h = h.substr(0, h.length() - 5).strip_edges()
			var hc = ""
			var hi = h.find("@")
			if hi >= 0:
				hc = h.substr(hi + 1).strip_edges()
				h = h.substr(0, hi).strip_edges()
			if not nodes.has(h): nodes[h] = []
			cur = {"id": h, "cond": hc, "once": once, "key": "seen.%s.%d" % [h, nodes[h].size()], "items": [], "src": "%s:%d" % [path.get_file(), n]}
			nodes[h].append(cur)
			continue
		if cur == null:
			errors.append("%s:%d text outside node" % [path, n])
			continue
		var c = ""
		if s.begins_with("{"):
			var j = s.find("}")
			c = s.substr(1, j - 1)
			s = s.substr(j + 1).strip_edges()
		if s.begins_with("->"):
			cur.items.append({"k": "goto", "to": s.substr(2).strip_edges(), "cond": c})
		elif s.begins_with("*"):
			var p = s.substr(1).strip_edges()
			var sp = p.find(" ")
			cur.items.append({"k": "cmd", "cmd": p if sp < 0 else p.substr(0, sp), "args": "" if sp < 0 else p.substr(sp + 1).strip_edges(), "cond": c})
		elif s.begins_with("?"):
			var parts = s.substr(1).split("|")
			var head = parts[0]
			var to = ""
			var a = head.find("->")
			if a >= 0:
				to = head.substr(a + 2).strip_edges()
				head = head.substr(0, a)
			var ch = {"k": "choice", "text": head.strip_edges(), "to": to, "cond": c, "do": ""}
			for i in range(1, parts.size()):
				var q = parts[i].strip_edges()
				if q.begins_with("if "): ch.cond = q.substr(3)
				elif q.begins_with("do "): ch.do = q.substr(3)
			cur.items.append(ch)
		else:
			var i = s.find(":")
			if i < 0 or i > 24:
				errors.append("%s:%d bad line: %s" % [path, n, s])
				continue
			var who = s.substr(0, i).strip_edges()
			var mood = ""
			var sl = who.find("/")
			if sl >= 0:
				mood = who.substr(sl + 1)
				who = who.substr(0, sl)
			cur.items.append({"k": "line", "who": who, "mood": mood, "text": s.substr(i + 1).strip_edges(), "cond": c})

func resolve(id):
	if not nodes.has(id): return null
	for v in nodes[id]:
		if v.once and G.f(v.key) != 0: continue
		if G.cond(v.cond): return v
	return null

# ---------------------------------------------------------------- room assembly
func assemble(id):
	var room = rooms[id]
	var cw = 0
	var maxr = 0
	for cn in room.chunks:
		if not chunks.has(cn):
			errors.append("room %s: unknown chunk %s" % [id, cn])
			continue
		cw += chunks[cn][0].length()
		maxr = max(maxr, chunks[cn].size())
	var H = max(23, maxr + 5)
	var W = max(cw, 40)
	var grid = PackedByteArray()
	grid.resize(W * H)
	var slots = {}
	var x0 = 0
	for cn in room.chunks:
		if not chunks.has(cn): continue
		var rows = chunks[cn]
		var R = rows.size()
		var y0 = H - (R + 2)
		var w = rows[0].length()
		for x in w:
			for y in R + 2:
				var ch = rows[min(y, R - 1)][x]
				if y >= R and not (ch in ["#", "~", "^"]): ch = "."
				if y >= R and ch == "^": ch = "#"
				var gx = x0 + x
				var gy = y0 + y
				if TILE.has(ch): grid[gy * W + gx] = TILE[ch]
				elif ch != "." and ch != " ":
					if not slots.has(ch): slots[ch] = []
					slots[ch].append(Vector2i(gx, gy))
		x0 += w
	for x in range(cw, W):
		for y in range(H - 3, H): grid[y * W + x] = 1
	if room.get("ceil", "0") == "1":
		for x in W:
			for y in 2:
				if grid[y * W + x] == 0: grid[y * W + x] = 1
	return {"W": W, "H": H, "grid": grid, "slots": slots}
