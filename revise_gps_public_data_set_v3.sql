-- create gps history table
drop table if exists gps_history;
-- TRUNCATE gps_history;
create table gps_history (
	idx integer,
	geom geometry(Point, 5179),
	geom_4326 geometry(Point, 4326)
);
insert into gps_history (idx, geom_4326)
	values(0, ST_SetSRID(ST_POINT(126.922195, 37.531512), 4326)),
	(1, ST_SetSRID(ST_POINT(126.924091, 37.529533), 4326)),
	(2, ST_SetSRID(ST_POINT(126.926244, 37.529736), 4326)),
	(3, ST_SetSRID(ST_POINT(126.928742, 37.529576), 4326)),
	(4, ST_SetSRID(ST_POINT(126.928369, 37.527664), 4326));
	
update gps_history 
	set geom = st_transform(
			geom_4326, 
			'+proj=longlat +ellps=WGS84 +datum=WGS84 +no_defs', -- WGS84, EPSG:4326
			'+proj=tmerc +lat_0=38 +lon_0=127.5 +k=0.9996 +x_0=1000000 +y_0=2000000 +ellps=GRS80 +units=m +no_defs' -- EPSG:5179
	);

-- find geometry object, has minimum distance from a point
DROP FUNCTION findMinDistanceGeometryObjectsByAPoint(point geometry);
create or replace function findMinDistanceGeometryObjectsByAPoint(
	point geometry
) Returns table (distance float, id integer, geom geometry, cp_point_on_line geometry) AS $$
DECLARE
	SRID integer := 5179; --SRID: 5179
	METER_SRID integer := 5179; --Massachusetts state plane meters
	LIMITS integer := 3;
BEGIN
	return query	
	select ST_DISTANCE(
		ST_Transform(r.geom, METER_SRID), 
		ST_Transform(point, METER_SRID)
	) as distance, 
	r.id as id,
	r.geom as geom,
	st_closestpoint(r.geom, point) as cp_point_on_line
	from roads r 
	order by r.geom <-> point
	limit LIMITS;
END; $$ 
Language plpgsql;

-- create nearest road geometry table by gps history
-- drop table if exists nearest_neighberhood_road_geom_public;
truncate nearest_neighberhood_road_geom_public;
insert into nearest_neighberhood_road_geom_public select 
	gh.idx::integer as idx,
	frst.id::integer as id,
	frst.distance as distance,
	frst.geom as geom,
	frst.cp_point_on_line as cp_point_on_line
from gps_history gh,
	LATERAL findMinDistanceGeometryObjectsByAPoint(ST_transform(gh.geom, 5179)) as frst;

-- find shortest path with two geometry
DROP FUNCTION if exists findShortestPath(integer,integer);
create or replace function findShortestPath(
	sourceId integer,
	targetId integer
) returns table (
	seq integer,
	node bigint,
	cost float,
	agg_cost float,
	geom geometry 
) AS $$
BEGIN
	return query
	SELECT pd.seq, pd.node, pd.cost, pd.agg_cost, r.geom as geom
	FROM pgr_dijkstra('
		  SELECT
			 id,
			 source,
			 target,
			 st_length(geom) as cost
		  FROM roads;',
		  sourceId,
		  targetId) as pd
		  join roads r
		  on pd.node = r.id;
END; $$ 
Language plpgsql;


-- drop table if exists shortest_path_public;
truncate shortest_path_public;
insert into shortest_path_public select 
	prev.idx,
	fsp.seq,
	prev.id as source,
	next.id as target,
	fsp.node,
	fsp.cost,
	fsp.agg_cost,
	fsp.geom
from nearest_neighberhood_road_geom_public prev
	inner join nearest_neighberhood_road_geom_public next
		on prev.idx + 1 = next.idx,
	lateral findshortestpath(prev.id, next.id) as fsp;