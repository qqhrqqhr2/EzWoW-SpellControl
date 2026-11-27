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

-- All Paladin standard blessings share a single per-caster slot on a target.
local PALADIN_MAIN_BLESSING_IDS = {
    -- Might
    19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916,
    -- Wisdom
    19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918,
    -- Kings
    20217, 25898,
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
