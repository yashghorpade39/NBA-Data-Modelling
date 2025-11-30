-- Example lookup to inspect raw player_seasons data
-- select * from player_seasons WHERE player_name like 'A.C.%';


-- Custom composite type to store one season of stats
-- Represents a single "season record" for a player
-- CREATE TYPE SEASON_STATS AS(
--     season INTEGER,
--     gp INTEGER,
--     pts REAL,
--     reb REAL,
--     ast REAL
-- );

-- Scoring category for a player's current season
-- CREATE TYPE scoring_class AS ENUM('star','good','average','bad');


-- Main cumulative players table
-- Each row is a snapshot of a player for a given season
-- CREATE TABLE PLAYERS(
--     player_name TEXT,
--     height TEXT,
--     college TEXT,
--     country TEXT,
--     draft_year TEXT,
--     draft_round TEXT,
--     draft_number TEXT,
--     season_stats season_stats[],          -- full history of seasons
--     scoring_class scoring_class,          -- scoring tier for current season
--     years_since_last_season INTEGER,      -- how long they’ve been inactive
--     current_season INTEGER,               -- snapshot season identifier
--     PRIMARY KEY(player_name, current_season)
-- );


-- Drop previous snapshot table if needed (dev use only)
DROP TABLE PLAYERS;


-- Example: find players who haven't appeared in 3+ years
select * from players where years_since_last_season > 2;


-- Insert the next season snapshot
-- Pulls last season's players (YESTERDAY) and the new season's stats (TODAY)
INSERT INTO PLAYERS
WITH YESTERDAY AS (
    SELECT * FROM players
    WHERE current_season = 2000
),
TODAY AS (
    SELECT * FROM player_seasons
    WHERE season = 2001
)

SELECT 
    -- Basic identity and bio fields
    COALESCE(t.player_name, y.player_name) AS player_name,
    COALESCE(t.height, y.height) AS height,
    COALESCE(t.college, y.college) AS college,
    COALESCE(t.country, y.country) AS country,
    COALESCE(t.draft_year, y.draft_year) AS draft_year,
    COALESCE(t.draft_round, y.draft_round) AS draft_round,
    COALESCE(t.draft_number, y.draft_number) AS draft_number,

    -- Build updated season history array
    CASE 
        -- Player is new this season
        WHEN y.season_stats IS NULL THEN
            ARRAY[ROW(t.season, t.gp, t.pts, t.reb, t.ast)::season_stats]

        -- Player has previous seasons and played this one
        WHEN t.season IS NOT NULL THEN
            y.season_stats || ARRAY[ROW(t.season, t.gp, t.pts, t.reb, t.ast)::season_stats]

        -- Player did not play this season
        ELSE y.season_stats
    END AS season_stats,

    -- Compute scoring tier for the current season
    CASE 
        WHEN t.season IS NOT NULL THEN
            CASE 
                WHEN t.pts > 20 THEN 'star'
                WHEN t.pts > 15 THEN 'good'
                WHEN t.pts > 10 THEN 'average'
                ELSE 'bad'
            END::scoring_class
        ELSE y.scoring_class
    END AS scoring_class,

    -- Track inactivity: reset to 0 if they played, otherwise increment
    CASE 
        WHEN t.season IS NOT NULL THEN 0
        ELSE y.years_since_last_season + 1
    END AS years_since_last_season,

    -- Advance the snapshot season
    COALESCE(t.season, y.current_season + 1) AS current_season

FROM TODAY t
FULL OUTER JOIN YESTERDAY y
    ON t.player_name = y.player_name;


-- Quick check for specific players
select * from players where player_name like 'Michael Jor%';


-- Unnest the season history for row-by-row inspection
WITH UNNESTED AS (    
    SELECT 
        player_name,
        UNNEST(season_stats) AS stats
    FROM players
    WHERE current_season = 2001
)
SELECT 
    player_name, 
    (stats::season_stats).*     -- expand composite type fields
FROM UNNESTED;


-- Compare first-season scoring vs latest-season scoring for star players
-- This identifies improvement ratios
SELECT 
    player_name,
    (season_stats[cardinality(season_stats)]::season_stats).pts /
        CASE 
            WHEN (season_stats[1]::season_stats).pts = 0 THEN 1 
            ELSE (season_stats[1]::season_stats).pts
        END AS stats_ratio
FROM players
WHERE scoring_class = 'star'
  AND current_season = '2001'
ORDER BY 2 DESC;
