' Idle/Incremental Business Simulator in QBASIC
' Simple turn-based business game

CONST MAX_UPGRADES = 5

TYPE UPGRADE
    name AS STRING * 20
    baseCost AS LONG
    level AS INTEGER
    incomePerLevel AS LONG
END TYPE

DIM SHARED upgrades(MAX_UPGRADES) AS UPGRADE

DIM SHARED money AS LONG
DIM SHARED incomePerTick AS LONG
DIM SHARED tick AS LONG

SUB InitGame
    money = 0
    incomePerTick = 1
    tick = 0

    ' Define upgrades
    upgrades(1).name = "Lemonade Stand"
    upgrades(1).baseCost = 10
    upgrades(1).level = 0
    upgrades(1).incomePerLevel = 1

    upgrades(2).name = "Food Truck"
    upgrades(2).baseCost = 100
    upgrades(2).level = 0
    upgrades(2).incomePerLevel = 5

    upgrades(3).name = "Small Store"
    upgrades(3).baseCost = 500
    upgrades(3).level = 0
    upgrades(3).incomePerLevel = 20

    upgrades(4).name = "Supermarket"
    upgrades(4).baseCost = 2000
    upgrades(4).level = 0
    upgrades(4).incomePerLevel = 100

    upgrades(5).name = "Corporate HQ"
    upgrades(5).baseCost = 10000
    upgrades(5).level = 0
    upgrades(5).incomePerLevel = 500
END SUB

FUNCTION UpgradeCost%(idx%)
    ' Cost grows with level: baseCost * (level + 1)
    UpgradeCost% = upgrades(idx%).baseCost * (upgrades(idx%).level + 1)
END FUNCTION

SUB RecalculateIncome
    DIM i AS INTEGER
    incomePerTick = 1 ' base income
    FOR i = 1 TO MAX_UPGRADES
        incomePerTick = incomePerTick + upgrades(i).level * upgrades(i).incomePerLevel
    NEXT i
END SUB

SUB ShowStatus
    CLS
    PRINT "==============================="
    PRINT "   IDLE BUSINESS SIMULATOR"
    PRINT "==============================="
    PRINT
    PRINT "Tick: "; tick
    PRINT "Money: $"; money
    PRINT "Income per tick: $"; incomePerTick
    PRINT
    PRINT "Upgrades:"
    DIM i AS INTEGER
    FOR i = 1 TO MAX_UPGRADES
        PRINT i; ". "; RTRIM$(upgrades(i).name); "  Level:"; upgrades(i).level;
        PRINT "  Next Cost:$"; UpgradeCost%(i)
    NEXT i
    PRINT
    PRINT "Actions:"
    PRINT "  [N] Next tick (time passes, you earn money)"
    PRINT "  [B] Buy upgrade"
    PRINT "  [Q] Quit game"
    PRINT
END SUB

SUB NextTick
    tick = tick + 1
    money = money + incomePerTick
END SUB

SUB BuyUpgrade
    DIM choice AS INTEGER
    DIM cost AS LONG

    PRINT
    PRINT "Enter upgrade number to buy (1-"; MAX_UPGRADES; "), or 0 to cancel:";
    INPUT choice

    IF choice = 0 THEN
        EXIT SUB
    END IF

    IF choice < 1 OR choice > MAX_UPGRADES THEN
        PRINT "Invalid choice. Press any key..."
        SLEEP
        EXIT SUB
    END IF

    cost = UpgradeCost%(choice)

    IF money < cost THEN
        PRINT "Not enough money! You need $"; cost; " but have $"; money
        PRINT "Press any key..."
        SLEEP
        EXIT SUB
    END IF

    money = money - cost
    upgrades(choice).level = upgrades(choice).level + 1
    RecalculateIncome

    PRINT
    PRINT "Purchased "; RTRIM$(upgrades(choice).name); " level "; upgrades(choice).level; "!"
    PRINT "New income per tick: $"; incomePerTick
    PRINT "Press any key..."
    SLEEP
END SUB

' ---------------- MAIN PROGRAM ----------------

CALL InitGame
CALL RecalculateIncome

DO
    CALL ShowStatus

    PRINT "Choose an action (N/B/Q): ";
    DIM action AS STRING
    action = ""
    WHILE action = ""
        action = UCASE$(INKEY$)
    WEND

    SELECT CASE action
        CASE "N"
            CALL NextTick
        CASE "B"
            CALL BuyUpgrade
        CASE "Q"
            EXIT DO
        CASE ELSE
            ' Ignore unknown keys
    END SELECT
LOOP

CLS
PRINT "Thanks for playing!"
PRINT "Final tick: "; tick
PRINT "Final money: $"; money
PRINT
PRINT "Press any key to exit..."
SLEEP
END
