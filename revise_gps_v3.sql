-- create gps history table
drop table if exists gps_history;
create table gps_history (
	idx integer,
	geom geometry
);
insert into gps_history (idx, geom)
	values(0, ST_SetSRID(ST_POINT(126.922195, 37.531512), 4326)),
	(1, ST_SetSRID(ST_POINT(126.924091, 37.529533), 4326)),
	(2, ST_SetSRID(ST_POINT(126.926244, 37.529736), 4326)),
	(3, ST_SetSRID(ST_POINT(126.928742, 37.529576), 4326)),
	(4, ST_SetSRID(ST_POINT(126.928369, 37.527664), 4326));


-- find geometry object, has minimum distance from a point
DROP FUNCTION findMinDistanceGeometryObjectsByAPoint(double precision,double precision);
create or replace function findMinDistanceGeometryObjectsByAPoint(
	point geometry
) Returns table (st_distance float, db_id numeric(10,0), geom geometry) AS $$
DECLARE
	SRID integer := 4326; --SRID: WGS84
	METER_SRID integer := 26986; --Massachusetts state plane meters
	LIMITS integer := 3;
BEGIN
	return query	
	select ST_DISTANCE(
		ST_Transform(dw.wkb_geometry, METER_SRID), 
		ST_Transform(point, METER_SRID)
	) as st_distance, 
	dw.db_id as db_id,
	dw.wkb_geometry as geom,
	ST_Project(point, geom) as cp_point_on_line
	from dw_rd_link_sample_wgs84 dw 
	order by wkb_geometry <-> point
	limit LIMITS;
END; $$ 
Language plpgsql;

-- create nearest road geometry table by gps history
drop table if exists nearest_neighberhood_road_geom;
create table nearest_neighberhood_road_geom as select 
	gh.idx::integer as idx,
	frst.db_id::integer as id,
	frst.distance as distance,
	gh.geom as geom,
	frst.cp_point_on_line as cp_point_on_line
from gps_history gh
	LATERAL findMinDistanceGeometryObjectsByAPoint(gh.geom) as frst

-- find shortest path with two geometry
DROP FUNCTION if exists findshortestpath(integer,integer);
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
	drop table if exists shortest_path;
	return query
	SELECT pd.seq, pd.node, pd.cost, pd.agg_cost, dw.wkb_geometry as geom
	FROM pgr_dijkstra('
		  SELECT
			 (source*100000+target)::integer as id,
			 source::integer,
			 target::integer,
			 cost
		  FROM edge_table;',
		  sourceId,
		  targetId) as pd
		  join dw_rd_link_sample_wgs84 dw
		  on pd.node = dw.db_id;
END; $$ 
Language plpgsql;


create table shortest_path as select 
	prev.idx,
	fsp.seq,
	prev.id as source,
	next.id as target,
	fsp.node,
	fsp.cost,
	fsp.agg_cost,
	fsp.geom
from nearest_neighberhood_road_geom prev
	inner join nearest_neighberhood_road_geom next
		on prev.idx + 1 = next.idx,
	lateral findshortestpath(prev.id, next.id) as fsp;