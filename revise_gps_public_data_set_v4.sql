-- DROP FUNCTION findMinDistanceGeometryObjectsByAPoint(point geometry);
create or replace function findMinDistanceGeometryObjectsByAPoint(
	point geometry
) Returns table (
		distance float, 
		id integer, 
		source integer,
		target integer,
		geom geometry, 
		cp_point_on_line geometry
) AS $$
DECLARE
	SRID integer := 5179; --SRID: 5179
	METER_SRID integer := 5179; --Massachusetts state plane meters
	LIMITS integer := 1;
BEGIN
	return query	
	select ST_DISTANCE(
		ST_Transform(r.geom, METER_SRID), 
		ST_Transform(point, METER_SRID)
	) as distance, 
	r.id as id,
	r.source as source,
	r.target as target,
	r.geom as geom,
	st_closestpoint(r.geom, point) as cp_point_on_line
	from roads_tlp r
	order by r.geom <-> point
	limit LIMITS;
END; $$ 
Language plpgsql;

-- create nearest road geometry table by gps history
CREATE TABLE if not exists nearest_neighberhood_road_geom_public (
    idx integer,
    id integer,
    source integer,
    target integer,
    distance double precision,
    geom geometry,
    cp_point_on_line geometry
);
truncate nearest_neighberhood_road_geom_public;
insert into nearest_neighberhood_road_geom_public select 
	gh.idx::integer as idx,
	frst.id::integer as id,
	frst.source:: integer as source,
	frst.target:: integer as target,
	frst.distance as distance,
	frst.geom as geom,
	frst.cp_point_on_line as cp_point_on_line
from gps_history gh,
	LATERAL findMinDistanceGeometryObjectsByAPoint(ST_transform(gh.geom, 5179)) as frst;

-- find shortest path with two geometry
-- DROP FUNCTION if exists findShortestPath(integer,integer);
create or replace function findShortestPath(
	sourceId integer,
	targetId integer,
	idx integer
) returns table (
	seq integer,
	node bigint,
	cost float,
	agg_cost float,
	geom geometry 
) AS $$
BEGIN
	raise notice '%idx source: %, target: %', idx, sourceId, targetId;
	
	return query
	SELECT pd.seq, pd.node, pd.cost, pd.agg_cost, r.geom as geom
	FROM pgr_dijkstra('
		  SELECT
			 id,
			 source,
			 target,
			 st_length(geom) as cost,
			 st_length(geom) as reverse_cost
		  FROM roads_tlp;',
		  sourceId,
		  targetId, false) as pd
		  join roads_tlp r
		  on pd.edge = r.id;
END; $$ 
Language plpgsql;


-- drop table if exists shortest_path_public;
CREATE TABLE if not exists shortest_path_public (
    idx integer,
    seq integer,
    source integer,
    target integer,
    node bigint,
    cost double precision,
    agg_cost double precision,
    geom geometry
);
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
	lateral findshortestpath(prev.target, next.source, prev.idx) as fsp;