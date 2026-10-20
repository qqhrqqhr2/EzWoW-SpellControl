local ADDON_NAME, NS = ...

NS.Spells = {}

-- Debuff type priority and EzWoW Style visual colors
NS.DEBUFF_TYPES = {
    Magic   = { order = 1, r = 0.25, g = 0.62, b = 1.00, hex = "409EFF", badge = "M" },
    Curse   = { order = 2, r = 0.68, g = 0.38, b = 0.96, hex = "AD61F5", badge = "C" },
    Disease = { order = 3, r = 0.85, g = 0.58, b = 0.24, hex = "D9943D", badge = "D" },
    Poison  = { order = 4, r = 0.24, g = 0.82, b = 0.42, hex = "3DD16B", badge = "P" },
}

-- Helper: In Classic/Forever, a buff learned at `learnedLvl` can only be cast on a target
-- whose level is at least `math.max(1, learnedLvl - 10)`.
local function R(id, rank, learnedLvl)
    return {
        id = id,
        rank = rank,
        learnedLvl = learnedLvl,
        minTargetLvl = math.max(1, learnedLvl - 10),
    }
end

-------------------------------------------------------------------------------
-- Class Dispel Definitions (Left-Click = Primary Dispel, Right-Click = Secondary Dispel)
-- Checked dynamically against the player's active (non-passive) spellbook.
-- `abolishAuraID` marks 8-second periodic cleanse buffs (Abolish Poison / Abolish Disease)
-- so the addon avoids telling the user to spam-click while the buff is already ticking.
-------------------------------------------------------------------------------
NS.CLASS_DISPELS = {
    PRIEST = {
        {
            key = "DISPEL_MAGIC",
            cures = { Magic = true },
            priority = 1,
            ranks = { R(527, 1, 18), R(988, 2, 36) },
        },
        {
            key = "ABOLISH_DISEASE",
            cures = { Disease = true },
            abolishAuraID = 552,
            priority = 2,
            ranks = { R(552, 1, 32) },
        },
        {
            key = "CURE_DISEASE",
            cures = { Disease = true },
            priority = 3,
            ranks = { R(528, 1, 14) },
        },
    },
    PALADIN = {
        {
            key = "CLEANSE",
            cures = { Magic = true, Poison = true, Disease = true },
            priority = 1,
            ranks = { R(4987, 1, 42) },
        },
        {
            key = "PURIFY",
            cures = { Poison = true, Disease = true },
            priority = 2,
            ranks = { R(1152, 1, 8) },
        },
    },
    DRUID = {
        {
            key = "ABOLISH_POISON",
            cures = { Poison = true },
            abolishAuraID = 2893,
            priority = 1,
            ranks = { R(2893, 1, 26) },
        },
        {
            key = "CURE_POISON",
            cures = { Poison = true },
            priority = 2,
            ranks = { R(8946, 1, 14) },
        },
        {
            key = "REMOVE_CURSE",
            cures = { Curse = true },
            priority = 3,
            ranks = { R(2782, 1, 24) },
        },
    },
    MAGE = {
        {
            key = "REMOVE_GREATER_CURSE",
            cures = { Curse = true, Magic = true },
            priority = 1,
            ranks = { R(412113, 1, 18) },
        },
        {
            key = "REMOVE_LESSER_CURSE",
            cures = { Curse = true },
            priority = 2,
            ranks = { R(475, 1, 18) },
        },
    },
    SHAMAN = {
        {
            key = "CLEANSE_SPIRIT",
            cures = { Curse = true, Disease = true, Poison = true },
            priority = 1,
            ranks = { R(51886, 1, 40) },
        },
        {
            key = "CURE_POISON_SHAMAN",
            cures = { Poison = true },
            priority = 2,
            ranks = { R(526, 1, 16) },
        },
        {
            key = "CURE_DISEASE_SHAMAN",
            cures = { Disease = true },
            priority = 3,
            ranks = { R(2870, 1, 22) },
        },
    },
    WARLOCK = {
        {
            key = "DEVOUR_MAGIC",
            isPetSpell = true,
            cures = { Magic = true },
            priority = 1,
            ranks = { R(19505, 1, 30), R(19731, 2, 38), R(19734, 3, 46), R(19736, 4, 54) },
        },
    },
}

-- All Paladin standard blessings share a single per-caster slot on a target
-- (Blessing of Salvation is separate in Forever and can stack alongside them).
local PALADIN_MAIN_BLESSING_IDS = {
    -- Might
    19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916,
    -- Wisdom
    19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918,
    -- Kings
    20217, 25898,
    -- Light
    19977, 19978, 19979, 25890,
    -- Sanctuary
    20911, 20912, 20913, 20914, 25899,
}

-------------------------------------------------------------------------------
-- Class Castable Buff Definitions (Passive / Talent auras strictly excluded!)
-- Ctrl + Left-Click  = Smart Primary Buff (or Slot 1)
-- Ctrl + Right-Click = Smart Secondary Buff (or Slot 2)
-------------------------------------------------------------------------------
NS.CLASS_BUFFS = {
    DRUID = {
        {
            key = "MARK_OF_THE_WILD",
            defaultSlot = 1, -- Ctrl + Left-Click
            smartOrder = 1,
            isSelfOnly = false,
            ranks = {
                R(1126, 1, 1),
                R(5232, 2, 10),
                R(6756, 3, 20),
                R(5234, 4, 30),
                R(8907, 5, 40),
                R(9884, 6, 50),
                R(9885, 7, 60),
            },
            groupRanks = {
                R(21849, 1, 50),
                R(21850, 2, 60),
            },
        },
        {
            key = "THORNS",
            defaultSlot = 2, -- Ctrl + Right-Click
            smartOrder = 2,
            isSelfOnly = false,
            ranks = {
                R(467, 1, 6),
                R(782, 2, 14),
                R(1075, 3, 24),
                R(8914, 4, 34),
                R(9756, 5, 44),
                R(9910, 6, 54),
            },
        },
    },

    PRIEST = {
        {
            key = "FORTITUDE",
            defaultSlot = 1, -- Ctrl + Left-Click
            smartOrder = 1,
            isSelfOnly = false,
            ranks = {
                R(1243, 1, 1),
                R(1244, 2, 12),
                R(1245, 3, 24),
                R(2791, 4, 36),
                R(10937, 5, 48),
                R(10938, 6, 60),
            },
            groupRanks = {
                R(21562, 1, 48),
                R(21564, 2, 60),
            },
        },
        {
            key = "INNER_FIRE",
            defaultSlot = 2,
            smartOrder = 2, -- On self, prioritize Inner Fire right after Fortitude
            isSelfOnly = true,
            ranks = {
                R(588, 1, 12),
                R(7128, 2, 20),
                R(602, 3, 30),
                R(1006, 4, 40),
                R(10951, 5, 50),
                R(10952, 6, 60),
            },
        },
        {
            key = "SPIRIT",
            defaultSlot = 2, -- Ctrl + Right-Click (if learned)
            smartOrder = 3,
            isSelfOnly = false,
            manaUsersOnly = true,
            ranks = {
                R(14752, 1, 30),
                R(14818, 2, 40),
                R(14819, 3, 50),
                R(27841, 4, 60),
            },
            groupRanks = {
                R(27681, 1, 60),
            },
        },
        {
            key = "SHADOW_PROT",
            defaultSlot = 2,
            smartOrder = 4,
            isSelfOnly = false,
            ranks = {
                R(976, 1, 30),
                R(10957, 2, 42),
                R(10958, 3, 56),
            },
            groupRanks = {
                R(27683, 1, 56),
            },
        },
        {
            key = "FEAR_WARD",
            defaultSlot = 2,
            smartOrder = 5,
            isOptionalBuff = true, -- Cast on demand via Ctrl+Right-Click, don't nag on every party member
            isSelfOnly = false,
            ranks = {
                R(6346, 1, 20),
            },
        },
    },

    MAGE = {
        {
            key = "ARCANE_INTELLECT",
            defaultSlot = 1, -- Ctrl + Left-Click
            smartOrder = 1,
            isSelfOnly = false,
            manaUsersOnly = true,
            ranks = {
                R(1459, 1, 1),
                R(1460, 2, 14),
                R(1461, 3, 28),
                R(10156, 4, 42),
                R(10157, 5, 56),
            },
            groupRanks = {
                R(23028, 1, 56),
            },
        },
        {
            key = "ICE_ARMOR",
            defaultSlot = 2, -- Ctrl + Right-Click (Self)
            smartOrder = 2,
            isSelfOnly = true,
            ranks = {
                R(168, 1, 1),
                R(7300, 2, 10),
                R(7301, 3, 20),
                R(7302, 1, 30),
                R(7320, 2, 40),
                R(10219, 3, 50),
                R(10220, 4, 60),
            },
            alsoSatisfiedBy = { 6117, 22782, 22783 },
        },
        {
            key = "MAGE_ARMOR",
            defaultSlot = 2,
            smartOrder = 3,
            isSelfOnly = true,
            ranks = {
                R(6117, 1, 34),
                R(22782, 2, 46),
                R(22783, 3, 58),
            },
            alsoSatisfiedBy = { 168, 7300, 7301, 7302, 7320, 10219, 10220 },
        },
        {
            key = "DAMPEN_MAGIC",
            defaultSlot = 2,
            smartOrder = 4,
            isOptionalBuff = true,
            isSelfOnly = false,
            ranks = {
                R(604, 1, 12),
                R(8450, 2, 24),
                R(8451, 3, 36),
                R(10173, 4, 48),
                R(10174, 5, 60),
            },
        },
        {
            key = "AMPLIFY_MAGIC",
            defaultSlot = 2,
            smartOrder = 5,
            isOptionalBuff = true,
            isSelfOnly = false,
            ranks = {
                R(1008, 1, 18),
                R(8455, 2, 30),
                R(10169, 3, 42),
                R(10170, 4, 54),
            },
        },
    },

    PALADIN = {
        {
            key = "BLESS_MIGHT",
            defaultSlot = 1, -- Ctrl + Left-Click (Auto-matched for melee/physical classes)
            smartOrder = 1,
            isSelfOnly = false,
            isMainBlessing = true,
            preferPhysicalClass = true,
            alsoSatisfiedBy = PALADIN_MAIN_BLESSING_IDS,
            ranks = {
                R(19740, 1, 4),
                R(19834, 2, 12),
                R(19835, 3, 22),
                R(19836, 4, 32),
                R(19837, 5, 42),
                R(19838, 6, 52),
                R(25291, 7, 60),
            },
            groupRanks = {
                R(25782, 1, 52),
                R(25916, 2, 60),
            },
        },
        {
            key = "BLESS_WISDOM",
            defaultSlot = 1, -- Auto-matched for mana classes
            smartOrder = 2,
            isSelfOnly = false,
            manaUsersOnly = true,
            isMainBlessing = true,
            preferManaClass = true,
            alsoSatisfiedBy = PALADIN_MAIN_BLESSING_IDS,
            ranks = {
                R(19742, 1, 14),
                R(19850, 2, 24),
                R(19852, 3, 34),
                R(19853, 4, 44),
                R(19854, 5, 54),
                R(25290, 6, 60),
            },
            groupRanks = {
                R(25894, 1, 54),
                R(25918, 2, 60),
            },
        },
        {
            key = "BLESS_KINGS",
            defaultSlot = 1,
            smartOrder = 3,
            isSelfOnly = false,
            isMainBlessing = true,
            alsoSatisfiedBy = PALADIN_MAIN_BLESSING_IDS,
            ranks = {
                R(20217, 1, 20),
            },
            groupRanks = {
                R(25898, 1, 60),
            },
        },
        {
            key = "BLESS_SALVATION",
            defaultSlot = 2, -- Ctrl + Right-Click (Stacks with main blessing in Forever!)
            smartOrder = 4,
            isSelfOnly = false,
            ranks = {
                R(1038, 1, 26),
            },
            groupRanks = {
                R(25895, 1, 60),
            },
        },
        {
            key = "RIGHTEOUS_FURY",
            defaultSlot = 2,
            smartOrder = 5,
            isOptionalBuff = true,
            isSelfOnly = true,
            ranks = {
                R(25780, 1, 16),
            },
        },
        {
            key = "BLESS_SANCTUARY",
            defaultSlot = 2,
            smartOrder = 6,
            isSelfOnly = false,
            isMainBlessing = true,
            alsoSatisfiedBy = PALADIN_MAIN_BLESSING_IDS,
            ranks = {
                R(20911, 1, 30),
                R(20912, 2, 40),
                R(20913, 3, 50),
                R(20914, 4, 60),
            },
            groupRanks = {
                R(25899, 1, 60),
            },
        },
        {
            key = "BLESS_LIGHT",
            defaultSlot = 2,
            smartOrder = 7,
            isSelfOnly = false,
            isMainBlessing = true,
            alsoSatisfiedBy = PALADIN_MAIN_BLESSING_IDS,
            ranks = {
                R(19977, 1, 40),
                R(19978, 2, 50),
                R(19979, 3, 60),
            },
            groupRanks = {
                R(25890, 1, 60),
            },
        },
    },

    SHAMAN = {
        {
            key = "LIGHTNING_SHIELD",
            defaultSlot = 1,
            smartOrder = 1,
            isSelfOnly = true,
            ranks = {
                R(324, 1, 8),
                R(325, 2, 16),
                R(905, 3, 24),
                R(945, 4, 32),
                R(8134, 5, 40),
                R(10431, 6, 48),
                R(10432, 7, 56),
            },
            alsoSatisfiedBy = { 52127, 52129, 52131, 52134, 52136, 52138, 974, 32593, 32594 },
        },
        {
            key = "EARTH_SHIELD",
            defaultSlot = 1,
            smartOrder = 2,
            isSelfOnly = false,
            ranks = {
                R(974, 1, 50),
                R(32593, 2, 60),
            },
        },
        {
            key = "WATER_BREATHING",
            defaultSlot = 2,
            smartOrder = 3,
            isOptionalBuff = true,
            isSelfOnly = false,
            ranks = {
                R(131, 1, 22),
            },
        },
        {
            key = "WATER_WALKING",
            defaultSlot = 2,
            smartOrder = 4,
            isOptionalBuff = true,
            isSelfOnly = false,
            ranks = {
                R(546, 1, 28),
            },
        },
    },

    WARLOCK = {
        {
            key = "DEMON_ARMOR",
            defaultSlot = 1,
            smartOrder = 1,
            isSelfOnly = true,
            ranks = {
                R(687, 1, 1),
                R(696, 2, 10),
                R(706, 1, 20),
                R(1086, 2, 30),
                R(11733, 3, 40),
                R(11734, 4, 50),
                R(11735, 5, 60),
            },
        },
        {
            key = "UNENDING_BREATH",
            defaultSlot = 2,
            smartOrder = 2,
            isOptionalBuff = true,
            isSelfOnly = false,
            ranks = {
                R(5697, 1, 16),
            },
        },
        {
            key = "DETECT_INVIS",
            defaultSlot = 2,
            smartOrder = 3,
            isOptionalBuff = true,
            isSelfOnly = false,
            ranks = {
                R(132, 1, 26),
                R(2970, 2, 38),
                R(11743, 3, 50),
            },
        },
    },

    WARRIOR = {
        {
            key = "BATTLE_SHOUT",
            defaultSlot = 1,
            smartOrder = 1,
            isSelfOnly = true,
            ranks = {
                R(6673, 1, 1),
                R(5242, 2, 12),
                R(6192, 3, 22),
                R(11549, 4, 32),
                R(11550, 5, 42),
                R(11551, 6, 52),
                R(25289, 7, 60),
            },
        },
        {
            key = "COMMANDING_SHOUT",
            defaultSlot = 2,
            smartOrder = 2,
            isSelfOnly = true,
            ranks = {
                R(469, 1, 20),
            },
        },
    },

    HUNTER = {
        {
            key = "ASPECT_HAWK",
            defaultSlot = 1,
            smartOrder = 1,
            isSelfOnly = true,
            ranks = {
                R(13165, 1, 10),
                R(14318, 2, 18),
                R(14319, 3, 28),
                R(14320, 4, 38),
                R(14321, 5, 48),
                R(14322, 6, 58),
                R(25296, 7, 60),
            },
        },
    },
}

-- Classes that do not use Mana (skip Spirit / Arcane Intellect / Blessing of Wisdom)
NS.NON_MANA_CLASSES = {
    WARRIOR = true,
    ROGUE = true,
}

-- Physical/Melee classes that prefer Blessing of Might when Paladin smart-buffs
NS.PHYSICAL_CLASSES = {
    WARRIOR = true,
    ROGUE = true,
    HUNTER = true,
}

-------------------------------------------------------------------------------
-- Crowd Control (CC / 메즈) Definitions & Creature-Type Eligibility
-- Left-Click  = Primary Valid CC for Target Creature Type
-- Right-Click = Secondary Valid CC for Target Creature Type
-------------------------------------------------------------------------------
local function RCC(id, rank, learnedLvl, duration)
    return {
        id = id,
        rank = rank,
        learnedLvl = learnedLvl,
        duration = duration or 20,
    }
end

-- UnitCreatureType(unit) returns (localizedName, creatureTypeID)
NS.CREATURE_TYPE_ID_MAP = {
    [1] = "BEAST",
    [2] = "DRAGONKIN",
    [3] = "DEMON",
    [4] = "ELEMENTAL",
    [5] = "GIANT",
    [6] = "UNDEAD",
    [7] = "HUMANOID",
    [8] = "CRITTER",
    [9] = "MECHANICAL",
}

NS.CREATURE_TYPE_LOCALE_MAP = {
    -- Korean
    ["야수"] = "BEAST",
    ["용족"] = "DRAGONKIN",
    ["악마"] = "DEMON",
    ["정령"] = "ELEMENTAL",
    ["거인"] = "GIANT",
    ["언데드"] = "UNDEAD",
    ["인간형"] = "HUMANOID",
    ["동물"] = "CRITTER",
    ["하찮은 동물"] = "CRITTER",
    ["작은 동물"] = "CRITTER",
    ["기계"] = "MECHANICAL",
    -- English
    ["Beast"] = "BEAST",
    ["Dragonkin"] = "DRAGONKIN",
    ["Demon"] = "DEMON",
    ["Elemental"] = "ELEMENTAL",
    ["Giant"] = "GIANT",
    ["Undead"] = "UNDEAD",
    ["Humanoid"] = "HUMANOID",
    ["Critter"] = "CRITTER",
    ["Mechanical"] = "MECHANICAL",
    -- German
    ["Wildtier"] = "BEAST",
    ["Drachkin"] = "DRAGONKIN",
    ["Dämon"] = "DEMON",
    ["Elementar"] = "ELEMENTAL",
    ["Riese"] = "GIANT",
    ["Untoter"] = "UNDEAD",
    ["Kleintier"] = "CRITTER",
    ["Mechanisch"] = "MECHANICAL",
    -- French
    ["Bête"] = "BEAST",
    ["Draconien"] = "DRAGONKIN",
    ["Démon"] = "DEMON",
    ["Élémentaire"] = "ELEMENTAL",
    ["Géant"] = "GIANT",
    ["Mort-vivant"] = "UNDEAD",
    ["Humanoïde"] = "HUMANOID",
    ["Bestiole"] = "CRITTER",
    ["Mécanique"] = "MECHANICAL",
    -- Spanish
    ["Bestia"] = "BEAST",
    ["Dragante"] = "DRAGONKIN",
    ["Demonio"] = "DEMON",
    ["Gigante"] = "GIANT",
    ["No-muerto"] = "UNDEAD",
    ["Humanoide"] = "HUMANOID",
    ["Sabandija"] = "CRITTER",
    ["Mecánico"] = "MECHANICAL",
    -- Russian
    ["Животное"] = "BEAST",
    ["Дракон"] = "DRAGONKIN",
    ["Демон"] = "DEMON",
    ["Элементаль"] = "ELEMENTAL",
    ["Великан"] = "GIANT",
    ["Нежить"] = "UNDEAD",
    ["Гуманоид"] = "HUMANOID",
    ["Существо"] = "CRITTER",
    ["Механизм"] = "MECHANICAL",
    -- Simplified & Traditional Chinese
    ["野兽"] = "BEAST",
    ["野獸"] = "BEAST",
    ["龙类"] = "DRAGONKIN",
    ["龍類"] = "DRAGONKIN",
    ["恶魔"] = "DEMON",
    ["惡魔"] = "DEMON",
    ["元素生物"] = "ELEMENTAL",
    ["巨人"] = "GIANT",
    ["亡灵"] = "UNDEAD",
    ["不死族"] = "UNDEAD",
    ["人型生物"] = "HUMANOID",
    ["小动物"] = "CRITTER",
    ["小動物"] = "CRITTER",
    ["机械"] = "MECHANICAL",
    ["機械"] = "MECHANICAL",
}

NS.CLASS_CCS = {
    DRUID = {
        {
            key = "HIBERNATE",
            priority = 1,
            breakMode = "FRAGILE",
            allowedTypes = { BEAST = true, DRAGONKIN = true },
            allowedTypeKeys = { "CTYPE_BEAST", "CTYPE_DRAGONKIN" },
            ranks = {
                RCC(2637,  1, 18, 20),
                RCC(18657, 2, 38, 30),
                RCC(18658, 3, 58, 40),
            },
        },
        {
            key = "ENTANGLING_ROOTS",
            priority = 2,
            breakMode = "ROOT", -- Root: may survive hits; breaks when debuff disappears or unit moves
            allowedTypes = nil, -- Usable on all target types
            ranks = {
                RCC(339,   1,  8, 12),
                RCC(1062,  2, 18, 15),
                RCC(5195,  3, 28, 18),
                RCC(5196,  4, 38, 21),
                RCC(9852,  5, 48, 24),
                RCC(9853,  6, 58, 27),
                RCC(26989, 7, 68, 27),
                RCC(53308, 8, 78, 27),
            },
        },
        {
            key = "CYCLONE",
            priority = 3,
            breakMode = "NEVER",
            allowedTypes = nil,
            ranks = {
                RCC(33786, 1, 70, 6),
            },
        },
    },

    MAGE = {
        {
            key = "POLYMORPH",
            priority = 1,
            breakMode = "FRAGILE",
            allowedTypes = { HUMANOID = true, BEAST = true, CRITTER = true },
            allowedTypeKeys = { "CTYPE_HUMANOID", "CTYPE_BEAST" },
            ranks = {
                RCC(118,   1,  8, 20),
                RCC(12824, 2, 20, 30),
                RCC(12825, 3, 40, 40),
                RCC(12826, 4, 60, 50),
            },
            alsoAuraIDs = { 28271, 28272, 28270, 61305, 61721, 61780 },
        },
        {
            key = "FROST_NOVA",
            priority = 2,
            breakMode = "ROOT",
            allowedTypes = nil,
            ranks = {
                RCC(122,   1, 10, 8),
                RCC(865,   2, 26, 8),
                RCC(6131,  3, 40, 8),
                RCC(10230, 4, 54, 8),
                RCC(27088, 5, 67, 8),
                RCC(42917, 6, 75, 8),
            },
        },
    },

    PRIEST = {
        {
            key = "SHACKLE_UNDEAD",
            priority = 1,
            breakMode = "FRAGILE",
            allowedTypes = { UNDEAD = true },
            allowedTypeKeys = { "CTYPE_UNDEAD" },
            ranks = {
                RCC(9484,  1, 20, 30),
                RCC(9485,  2, 40, 40),
                RCC(10955, 3, 60, 50),
            },
        },
        {
            key = "MIND_CONTROL",
            priority = 2,
            breakMode = "NEVER",
            allowedTypes = { HUMANOID = true },
            allowedTypeKeys = { "CTYPE_HUMANOID" },
            ranks = {
                RCC(605,   1, 30, 60),
                RCC(10911, 2, 44, 60),
                RCC(10912, 3, 58, 60),
            },
        },
        {
            key = "PSYCHIC_SCREAM",
            priority = 3,
            breakMode = "CHANCE",
            allowedTypes = nil,
            blockedTypes = { UNDEAD = true, MECHANICAL = true },
            ranks = {
                RCC(8122,  1, 14, 8),
                RCC(8124,  2, 28, 8),
                RCC(10888, 3, 42, 8),
                RCC(10890, 4, 56, 8),
            },
        },
    },

    WARLOCK = {
        {
            key = "BANISH",
            priority = 1,
            breakMode = "NEVER",
            allowedTypes = { DEMON = true, ELEMENTAL = true },
            allowedTypeKeys = { "CTYPE_DEMON", "CTYPE_ELEMENTAL" },
            ranks = {
                RCC(710,   1, 28, 20),
                RCC(18647, 2, 48, 30),
            },
        },
        {
            key = "FEAR",
            priority = 2,
            breakMode = "CHANCE",
            allowedTypes = nil,
            blockedTypes = { UNDEAD = true, MECHANICAL = true },
            ranks = {
                RCC(5782,  1,  8, 10),
                RCC(6213,  2, 32, 15),
                RCC(6215,  3, 56, 20),
            },
        },
        {
            key = "SEDUCTION",
            isPetSpell = true,
            priority = 3,
            breakMode = "FRAGILE",
            allowedTypes = { HUMANOID = true },
            allowedTypeKeys = { "CTYPE_HUMANOID" },
            ranks = {
                RCC(6358,  1, 26, 15),
            },
        },
        {
            key = "HOWL_OF_TERROR",
            priority = 4,
            breakMode = "CHANCE",
            allowedTypes = nil,
            blockedTypes = { UNDEAD = true, MECHANICAL = true },
            ranks = {
                RCC(5484,  1, 40, 10),
                RCC(17928, 2, 54, 15),
            },
        },
    },

    ROGUE = {
        {
            key = "SAP",
            priority = 1,
            breakMode = "FRAGILE",
            allowedTypes = { HUMANOID = true, BEAST = true, DEMON = true, DRAGONKIN = true },
            allowedTypeKeys = { "CTYPE_HUMANOID", "CTYPE_BEAST", "CTYPE_DEMON", "CTYPE_DRAGONKIN" },
            ranks = {
                RCC(6770,  1, 10, 25),
                RCC(2070,  2, 28, 35),
                RCC(11297, 3, 48, 45),
                RCC(51724, 4, 71, 45),
            },
        },
        {
            key = "BLIND",
            priority = 2,
            breakMode = "FRAGILE",
            allowedTypes = nil,
            ranks = {
                RCC(2094,  1, 34, 10),
            },
        },
        {
            key = "GOUGE",
            priority = 3,
            breakMode = "FRAGILE",
            allowedTypes = nil,
            ranks = {
                RCC(1776,  1,  6, 4),
                RCC(1777,  2, 18, 4),
                RCC(8629,  3, 32, 4),
                RCC(11285, 4, 46, 4),
                RCC(11286, 5, 58, 4),
            },
        },
    },

    HUNTER = {
        {
            key = "SCARE_BEAST",
            priority = 1,
            breakMode = "CHANCE",
            allowedTypes = { BEAST = true },
            allowedTypeKeys = { "CTYPE_BEAST" },
            ranks = {
                RCC(1513,  1, 14, 10),
                RCC(14326, 2, 30, 15),
                RCC(14327, 3, 46, 20),
            },
        },
        {
            key = "WYVERN_STING",
            priority = 2,
            breakMode = "FRAGILE",
            allowedTypes = nil,
            ranks = {
                RCC(19386, 1, 40, 12),
                RCC(24132, 2, 50, 12),
                RCC(24133, 3, 60, 12),
                RCC(49011, 4, 70, 12),
                RCC(49012, 5, 80, 12),
            },
        },
        {
            key = "FREEZING_TRAP",
            priority = 3,
            breakMode = "FRAGILE",
            allowedTypes = nil,
            ranks = {
                RCC(1499,  1, 20, 10),
                RCC(14310, 2, 40, 15),
                RCC(14311, 3, 60, 20),
            },
            alsoAuraIDs = { 3355, 14308, 14309 },
        },
    },

    PALADIN = {
        {
            key = "TURN_UNDEAD",
            priority = 1,
            breakMode = "CHANCE",
            allowedTypes = { UNDEAD = true, DEMON = true },
            allowedTypeKeys = { "CTYPE_UNDEAD", "CTYPE_DEMON" },
            ranks = {
                RCC(2878,  1, 24, 10),
                RCC(5627,  2, 38, 15),
                RCC(10326, 3, 52, 20),
            },
        },
        {
            key = "REPENTANCE",
            priority = 2,
            breakMode = "FRAGILE",
            allowedTypes = { HUMANOID = true, DEMON = true, DRAGONKIN = true, GIANT = true, UNDEAD = true },
            allowedTypeKeys = { "CTYPE_HUMANOID", "CTYPE_DEMON", "CTYPE_DRAGONKIN", "CTYPE_GIANT", "CTYPE_UNDEAD" },
            ranks = {
                RCC(20066, 1, 40, 6),
            },
        },
        {
            key = "HAMMER_OF_JUSTICE",
            priority = 3,
            breakMode = "NEVER",
            allowedTypes = nil,
            ranks = {
                RCC(853,   1,  8, 3),
                RCC(5588,  2, 24, 4),
                RCC(5589,  3, 40, 5),
                RCC(10308, 4, 54, 6),
            },
        },
    },

    SHAMAN = {
        {
            key = "HEX",
            priority = 1,
            breakMode = "CHANCE",
            allowedTypes = { HUMANOID = true, BEAST = true },
            allowedTypeKeys = { "CTYPE_HUMANOID", "CTYPE_BEAST" },
            ranks = {
                RCC(51514, 1, 80, 30),
            },
        },
        {
            key = "FROST_SHOCK",
            priority = 2,
            breakMode = "NEVER",
            allowedTypes = nil,
            ranks = {
                RCC(8056,  1, 20, 8),
                RCC(8058,  2, 34, 8),
                RCC(10472, 3, 46, 8),
                RCC(10473, 4, 58, 8),
            },
        },
    },

    WARRIOR = {
        {
            key = "INTIMIDATING_SHOUT",
            priority = 1,
            breakMode = "CHANCE",
            allowedTypes = nil,
            blockedTypes = { UNDEAD = true, MECHANICAL = true },
            ranks = {
                RCC(5246,  1, 22, 8),
            },
        },
        {
            key = "HAMSTRING",
            priority = 2,
            breakMode = "NEVER",
            allowedTypes = nil,
            ranks = {
                RCC(1715,  1,  8, 15),
                RCC(7372,  2, 32, 15),
                RCC(7373,  3, 54, 15),
            },
        },
    },
}

