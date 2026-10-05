-- =====================================================================
--  Cours PostgreSQL / PostGIS : lotissement de MALICOUNDA EST
--  Script complet du formateur (chapitres 1 à 10)
--  Base : Malicounda_EST   —   SRID : 32628 (WGS 84 / UTM 28 N)
--
--  Prérequis : le dump QGIS « Malicouda_EST.sql » a été exécuté dans la
--  base Malicounda_EST APRÈS le CREATE EXTENSION du chapitre 1.
--  Le script s'exécute de haut en bas dans l'outil de requête de pgAdmin
--  (ou : psql -d Malicounda_EST -f malicounda_est_cours.sql).
-- =====================================================================


-- ---------------------------------------------------------------------
-- CHAPITRE 1 — Préparer la base
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS postgis;
SELECT PostGIS_Full_Version();

CREATE SCHEMA IF NOT EXISTS brut;   -- données telles que livrées par QGIS
CREATE SCHEMA IF NOT EXISTS cad;    -- tables propres, exploitées en cours


-- ---------------------------------------------------------------------
-- CHAPITRE 2 — Ranger la table importée
-- (le dump crée public."malicouda est" ; on la range dans brut)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS brut.lots_qgis CASCADE;
ALTER TABLE public."malicouda est" SET SCHEMA brut;
ALTER TABLE brut."malicouda est" RENAME TO lots_qgis;


-- ---------------------------------------------------------------------
-- CHAPITRE 3 — Découvrir la table
-- ---------------------------------------------------------------------
SELECT COUNT(*) FROM brut.lots_qgis;

SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'brut' AND table_name = 'lots_qgis'
ORDER BY ordinal_position;

SELECT ogc_fid, "n° du lot", superficie
FROM brut.lots_qgis
LIMIT 5;

SELECT GeometryType(wkb_geometry) AS type_geom,
       ST_NDims(wkb_geometry)     AS dimensions,
       ST_SRID(wkb_geometry)      AS srid,
       COUNT(*)                   AS nombre
FROM brut.lots_qgis
GROUP BY 1, 2, 3;


-- ---------------------------------------------------------------------
-- CHAPITRE 4 — Créer la table de travail cad.parcelles
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS cad.parcelles CASCADE;

CREATE TABLE cad.parcelles (
    id           INTEGER PRIMARY KEY,           -- reprend ogc_fid
    num_lot      VARCHAR(80),
    commune      VARCHAR(80),
    village      VARCHAR(80),
    lotissement  VARCHAR(80),
    num_dcm      VARCHAR(80),
    num_arrete   VARCHAR(80),
    nicad        VARCHAR(80),
    superficie   NUMERIC(10,0),                 -- surface déclarée (m²)
    prenom       VARCHAR(80),
    nom          VARCHAR(80),
    num_cni      VARCHAR(80),
    geom         geometry(MultiPolygon, 32628)  -- 2D, UTM 28 N
);

INSERT INTO cad.parcelles
      (id, num_lot, commune, village, lotissement, num_dcm, num_arrete,
       nicad, superficie, prenom, nom, num_cni, geom)
SELECT ogc_fid,
       NULLIF(TRIM("n° du lot"), ''),
       commune,
       village,
       "nom lotiss",
       "n ° dcm",
       "n° arrete",
       "nicad du l",
       superficie,
       NULLIF(TRIM(prenom), ''),
       NULLIF(TRIM(nom), ''),
       "n° cni",
       ST_Force2D(wkb_geometry)
FROM brut.lots_qgis;

CREATE INDEX idx_parcelles_geom    ON cad.parcelles USING GIST (geom);
CREATE INDEX idx_parcelles_num_lot ON cad.parcelles (num_lot);

COMMENT ON TABLE  cad.parcelles            IS 'Lots du lotissement de Malicounda Est';
COMMENT ON COLUMN cad.parcelles.superficie IS 'Surface déclarée en m² (issue du plan)';

ANALYZE cad.parcelles;

SELECT COUNT(*) FROM cad.parcelles;


-- ---------------------------------------------------------------------
-- CHAPITRE 5 — Les bases du SQL : lire et résumer
-- ---------------------------------------------------------------------
-- 5.1 Choisir les colonnes et les lignes
SELECT id, num_lot, superficie
FROM cad.parcelles
WHERE superficie > 1000
ORDER BY superficie DESC
LIMIT 10;

-- 5.2 Combiner des conditions
SELECT id, num_lot, superficie
FROM cad.parcelles
WHERE superficie BETWEEN 295 AND 305
  AND nom IS NOT NULL
ORDER BY num_lot
LIMIT 10;

SELECT id, num_lot FROM cad.parcelles WHERE num_lot IN ('3709', '3710');

-- 5.3 Chercher dans du texte
SELECT num_lot FROM cad.parcelles WHERE num_lot LIKE 'LOT%'  LIMIT 10;
SELECT num_lot FROM cad.parcelles WHERE num_lot LIKE '%;%'   LIMIT 10;
SELECT num_lot FROM cad.parcelles WHERE num_lot ILIKE '%bis%';

-- 5.4 Les valeurs manquantes
SELECT COUNT(*) AS sans_numero FROM cad.parcelles WHERE num_lot IS NULL;

SELECT COUNT(*)          AS total,
       COUNT(num_lot)    AS avec_numero,
       COUNT(nom)        AS avec_proprietaire,
       COUNT(nicad)      AS avec_nicad
FROM cad.parcelles;

-- 5.5 Valeurs distinctes
SELECT DISTINCT commune, village, lotissement FROM cad.parcelles;
SELECT COUNT(DISTINCT num_lot) AS numeros_differents FROM cad.parcelles;

-- 5.6 Fonctions d'agrégat
SELECT COUNT(*)                 AS nb_lots,
       MIN(superficie)          AS mini_m2,
       MAX(superficie)          AS maxi_m2,
       ROUND(AVG(superficie))   AS moyenne_m2,
       SUM(superficie) / 10000  AS total_ha
FROM cad.parcelles;

-- 5.7 Regrouper : GROUP BY et HAVING
SELECT superficie, COUNT(*) AS nombre
FROM cad.parcelles
GROUP BY superficie
ORDER BY nombre DESC
LIMIT 5;

SELECT num_lot, COUNT(*) AS nombre
FROM cad.parcelles
WHERE num_lot IS NOT NULL
GROUP BY num_lot
HAVING COUNT(*) > 1
ORDER BY nombre DESC, num_lot
LIMIT 15;

-- 5.8 Classer avec CASE
SELECT CASE
         WHEN superficie < 100  THEN '1. moins de 100 m²'
         WHEN superficie < 300  THEN '2. 100 à 299 m²'
         WHEN superficie <= 310 THEN '3. 300 à 310 m² (standard)'
         WHEN superficie < 1000 THEN '4. 311 à 999 m²'
         ELSE                        '5. 1000 m² et plus'
       END       AS classe,
       COUNT(*)  AS nombre
FROM cad.parcelles
GROUP BY classe
ORDER BY classe;

-- 5.9 Fonctions sur le texte
SELECT num_lot,
       UPPER(num_lot)                  AS majuscules,
       LENGTH(num_lot)                 AS longueur,
       SPLIT_PART(num_lot, ';', 1)     AS premier_numero,
       CONCAT_WS(' ', prenom, nom)     AS proprietaire
FROM cad.parcelles
WHERE num_lot LIKE '%;%'
LIMIT 5;

-- Propriétaires multiples fusionnés par la jointure QGIS (séparateur « || »)
SELECT COUNT(*) AS lots_multi_proprietaires
FROM cad.parcelles
WHERE prenom LIKE '%||%' OR nom LIKE '%||%';


-- ---------------------------------------------------------------------
-- CHAPITRE 6 — Modifier les données en sécurité
-- ---------------------------------------------------------------------
-- 6.1 Ajouter des colonnes calculées
ALTER TABLE cad.parcelles ADD COLUMN surface_calc NUMERIC(10,2);
UPDATE cad.parcelles SET surface_calc = ROUND(ST_Area(geom)::numeric, 2);

ALTER TABLE cad.parcelles ADD COLUMN type_numero VARCHAR(20);
UPDATE cad.parcelles
SET type_numero = CASE
      WHEN num_lot IS NULL              THEN 'absent'
      WHEN num_lot ~ '^[0-9]+$'         THEN 'numerique'
      WHEN num_lot LIKE '%;%'           THEN 'multiple'
      WHEN num_lot ILIKE 'LOT%'         THEN 'ancien (LOT)'
      ELSE                                   'avec suffixe'
    END;

SELECT type_numero, COUNT(*) FROM cad.parcelles GROUP BY type_numero ORDER BY 2 DESC;

-- 6.2 Supprimer les débris dans une transaction
BEGIN;
SELECT COUNT(*) FROM cad.parcelles WHERE ST_Area(geom) < 1;   -- voir avant
CREATE TABLE cad.debris AS
    SELECT * FROM cad.parcelles WHERE ST_Area(geom) < 1;     -- garder une trace
DELETE FROM cad.parcelles WHERE ST_Area(geom) < 1;
SELECT COUNT(*) FROM cad.parcelles;                          -- vérifier après
COMMIT;                                                      -- ou ROLLBACK;

-- 6.3 Une contrainte qui échoue... et pourquoi
-- ALTER TABLE cad.parcelles ADD CONSTRAINT uq_num_lot UNIQUE (num_lot);
--   ERREUR : could not create unique index ... Key (num_lot)=(...) is duplicated.
ALTER TABLE cad.parcelles
    ADD CONSTRAINT ck_superficie_positive CHECK (superficie > 0);


-- ---------------------------------------------------------------------
-- CHAPITRE 7 — Plusieurs tables : clés et jointures
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS cad.proprietaires CASCADE;

CREATE TABLE cad.proprietaires (
    id      SERIAL PRIMARY KEY,
    prenom  VARCHAR(80),
    nom     VARCHAR(80) NOT NULL,
    UNIQUE (prenom, nom)
);

INSERT INTO cad.proprietaires (prenom, nom)
SELECT DISTINCT prenom, nom
FROM cad.parcelles
WHERE nom IS NOT NULL
ORDER BY nom, prenom;

ALTER TABLE cad.parcelles
    ADD COLUMN proprietaire_id INTEGER REFERENCES cad.proprietaires (id);

UPDATE cad.parcelles p
SET proprietaire_id = pr.id
FROM cad.proprietaires pr
WHERE pr.nom = p.nom
  AND pr.prenom IS NOT DISTINCT FROM p.prenom;

SELECT COUNT(*) AS proprietaires FROM cad.proprietaires;
SELECT COUNT(*) AS lots_relies    FROM cad.parcelles WHERE proprietaire_id IS NOT NULL;

-- 7.1 Jointure interne
SELECT p.num_lot, p.superficie, pr.prenom, pr.nom
FROM cad.parcelles p
JOIN cad.proprietaires pr ON pr.id = p.proprietaire_id
ORDER BY pr.nom, pr.prenom
LIMIT 10;

-- 7.2 Jointure externe : nombre de lots par propriétaire
SELECT pr.id, COUNT(p.id) AS nb_lots, SUM(p.superficie) AS surface_m2
FROM cad.proprietaires pr
LEFT JOIN cad.parcelles p ON p.proprietaire_id = pr.id
GROUP BY pr.id
ORDER BY nb_lots DESC
LIMIT 5;

-- 7.3 Sous-requête : lots plus grands que la moyenne
SELECT COUNT(*) AS lots_plus_grands_que_moyenne
FROM cad.parcelles
WHERE superficie > (SELECT AVG(superficie) FROM cad.parcelles);

-- 7.4 Requête nommée avec WITH
WITH par_proprietaire AS (
    SELECT proprietaire_id, COUNT(*) AS nb_lots
    FROM cad.parcelles
    WHERE proprietaire_id IS NOT NULL
    GROUP BY proprietaire_id
)
SELECT nb_lots, COUNT(*) AS nb_proprietaires
FROM par_proprietaire
GROUP BY nb_lots
ORDER BY nb_lots;


-- ---------------------------------------------------------------------
-- CHAPITRE 8 — Requêtes spatiales
-- ---------------------------------------------------------------------
-- 8.1 Mesures
SELECT num_lot,
       superficie,
       ROUND(ST_Area(geom)::numeric, 1)      AS surface_m2,
       ROUND(ST_Perimeter(geom)::numeric, 1) AS perimetre_m
FROM cad.parcelles
WHERE num_lot IN ('3709', '3710');

SELECT ROUND((SUM(ST_Area(geom)) / 10000)::numeric, 2) AS surface_totale_ha
FROM cad.parcelles;

-- 8.2 Surface déclarée et surface calculée
SELECT COUNT(*) FILTER (WHERE ABS(superficie - ST_Area(geom)) <= 1) AS ecart_max_1m2,
       COUNT(*) FILTER (WHERE ABS(superficie - ST_Area(geom)) >  1) AS ecart_plus_1m2
FROM cad.parcelles;

-- 8.3 Coordonnées : UTM puis GPS
SELECT num_lot,
       ROUND(ST_X(ST_PointOnSurface(geom))::numeric, 2) AS x_utm,
       ROUND(ST_Y(ST_PointOnSurface(geom))::numeric, 2) AS y_utm,
       ROUND(ST_X(ST_Transform(ST_PointOnSurface(geom), 4326))::numeric, 6) AS longitude,
       ROUND(ST_Y(ST_Transform(ST_PointOnSurface(geom), 4326))::numeric, 6) AS latitude
FROM cad.parcelles
WHERE num_lot = '3710';

-- 8.4 Les voisins d'un lot
SELECT v.num_lot, v.superficie
FROM cad.parcelles p
JOIN cad.parcelles v ON ST_Touches(p.geom, v.geom)
WHERE p.num_lot = '3710'
ORDER BY v.num_lot;

-- 8.5 Les lots à moins de 50 m d'un lot donné
SELECT COUNT(*) AS lots_a_moins_de_50m
FROM cad.parcelles p
JOIN cad.parcelles v ON ST_DWithin(p.geom, v.geom, 50) AND v.id <> p.id
WHERE p.num_lot = '3710';

-- 8.6 Les 5 lots les plus proches d'un point GPS
SELECT num_lot,
       ROUND(ST_Distance(geom, pt)::numeric, 1) AS distance_m
FROM cad.parcelles,
     ST_Transform(ST_SetSRID(ST_MakePoint(-16.9554, 14.4571), 4326), 32628) AS pt
ORDER BY geom <-> pt
LIMIT 5;

-- 8.7 Reconstituer les îlots
ALTER TABLE cad.parcelles ADD COLUMN ilot INTEGER;

UPDATE cad.parcelles p
SET ilot = c.ilot
FROM (
    SELECT id,
           ST_ClusterDBSCAN(geom, eps := 0.5, minpoints := 1) OVER () + 1 AS ilot
    FROM cad.parcelles
) AS c
WHERE c.id = p.id;

DROP TABLE IF EXISTS cad.ilots;
CREATE TABLE cad.ilots AS
SELECT ilot                               AS id,
       COUNT(*)                           AS nb_lots,
       ROUND(SUM(ST_Area(geom))::numeric) AS surface_m2,
       ST_Multi(ST_Union(geom))::geometry(MultiPolygon, 32628) AS geom
FROM cad.parcelles
GROUP BY ilot;

ALTER TABLE cad.ilots ADD PRIMARY KEY (id);
CREATE INDEX idx_ilots_geom ON cad.ilots USING GIST (geom);

SELECT COUNT(*) AS nb_ilots, MAX(nb_lots) AS plus_grand_ilot FROM cad.ilots;

-- 8.8 Lots qui se chevauchent
SELECT a.num_lot AS lot_a,
       b.num_lot AS lot_b,
       ROUND(ST_Area(ST_Intersection(a.geom, b.geom))::numeric, 2) AS chevauchement_m2
FROM cad.parcelles a
JOIN cad.parcelles b ON a.id < b.id
                     AND ST_Overlaps(a.geom, b.geom)
                     AND ST_Area(ST_Intersection(a.geom, b.geom)) > 0.01
ORDER BY chevauchement_m2 DESC
LIMIT 10;


-- ---------------------------------------------------------------------
-- CHAPITRE 9 — Contrôle qualité : une vue des anomalies
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW cad.v_anomalies AS
SELECT ROW_NUMBER() OVER () AS gid, a.*      -- gid : clé unique pour QGIS
FROM (
SELECT id, num_lot, 'numéro absent' AS anomalie, geom
FROM cad.parcelles WHERE num_lot IS NULL
UNION ALL
SELECT id, num_lot, 'numéro en double', geom
FROM cad.parcelles
WHERE num_lot IN (SELECT num_lot FROM cad.parcelles
                  GROUP BY num_lot HAVING COUNT(*) > 1)
UNION ALL
SELECT id, num_lot, 'lot très petit (< 100 m²)', geom
FROM cad.parcelles WHERE ST_Area(geom) < 100
UNION ALL
SELECT a.id, a.num_lot, 'chevauche un autre lot', a.geom
FROM cad.parcelles a
WHERE EXISTS (SELECT 1 FROM cad.parcelles b
              WHERE b.id <> a.id
                AND ST_Overlaps(a.geom, b.geom)
                AND ST_Area(ST_Intersection(a.geom, b.geom)) > 0.01)
UNION ALL
SELECT id, num_lot, 'géométrie invalide', geom
FROM cad.parcelles WHERE NOT ST_IsValid(geom)
) AS a;

SELECT anomalie, COUNT(*) AS nombre
FROM cad.v_anomalies
GROUP BY anomalie
ORDER BY nombre DESC;


-- ---------------------------------------------------------------------
-- CHAPITRE 10 — Vues, copie pour les étudiants, droits
-- ---------------------------------------------------------------------
-- 10.1 Vue de synthèse par îlot
CREATE OR REPLACE VIEW cad.v_ilots_occupation AS
SELECT i.id,
       i.nb_lots,
       COUNT(p.proprietaire_id)                          AS lots_attribues,
       ROUND(100.0 * COUNT(p.proprietaire_id) / i.nb_lots) AS taux_pct,
       i.geom
FROM cad.ilots i
JOIN cad.parcelles p ON p.ilot = i.id
GROUP BY i.id, i.nb_lots, i.geom;

SELECT CASE WHEN taux_pct = 100 THEN 'complet'
            WHEN taux_pct = 0   THEN 'vide'
            ELSE 'partiel' END AS etat,
       COUNT(*) AS nb_ilots
FROM cad.v_ilots_occupation
GROUP BY etat ORDER BY etat;

-- 10.2 Copie anonymisée pour les étudiants
CREATE SCHEMA IF NOT EXISTS formation;
DROP TABLE IF EXISTS formation.parcelles;

CREATE TABLE formation.parcelles AS
SELECT p.id, p.num_lot, p.superficie, p.ilot, p.proprietaire_id,
       CASE WHEN p.proprietaire_id IS NULL THEN NULL
            ELSE 'Propriétaire ' || LPAD(p.proprietaire_id::text, 4, '0')
       END AS proprietaire,
       p.geom
FROM cad.parcelles p;

ALTER TABLE formation.parcelles ADD PRIMARY KEY (id);
CREATE INDEX ON formation.parcelles USING GIST (geom);

-- 10.3 Un rôle « étudiant » en lecture seule sur la copie
-- (à lancer une fois ; choisir un vrai mot de passe)
-- CREATE ROLE etudiant LOGIN PASSWORD 'a_changer';
-- GRANT CONNECT ON DATABASE "Malicounda_EST" TO etudiant;
-- GRANT USAGE  ON SCHEMA formation TO etudiant;
-- GRANT SELECT ON ALL TABLES IN SCHEMA formation TO etudiant;
