
-- DROP FUNCTION findMinDistanceGeometryObjectsByAPoint(point geometry, route_id varchar(64));
create or replace function findMinDistanceGeometryObjectsByAPoint(
	point geometry,
	route_id varchar(64)
) Returns table ( 
		vertex_id bigint, 
		cp_point_on_road geometry
) AS $$
DECLARE
	SRID integer := 5179; --SRID: 5179
	LIMITS integer := 1;
begin
	return query
	with minimumDistanceGeometryOnRoad as (
		select 
			st_distance(r.geom, point) as distance,
			r.geom as geom,
			r.source,
			r.target,
			st_closestpoint(r.geom, point) as cp_point_on_road
		from roads_tlp r
		order by r.geom <-> point
		limit LIMITS
	), new_vertices as (
		insert into 
			roads_tlp_vertices_pgr(
				the_geom,
				route_id
			)
		select 
			mdgr.cp_point_on_road as the_geom,
			route_id
		from minimumDistanceGeometryOnRoad mdgr
		returning id, the_geom as point_geom
	), new_edge1 as (
		insert into 
			roads_tlp (
				geom, 
				source,
				target,
				route_id
			)
		select 
			st_geometryn(st_split(st_snap(mdgr.geom, nv.point_geom, 0.000001), nv.point_geom), 1), 
			mdgr.source, 
			nv.id,
			route_id
		from minimumDistanceGeometryOnRoad mdgr 
		inner join new_vertices nv on st_equals(mdgr.cp_point_on_road, nv.point_geom)
		returning geom, source, target
	), new_edge2 as (
		insert into 
			roads_tlp (
				geom,
				source,
				target,
				route_id
			)
		select 
			st_geometryn(st_split(st_snap(mdgr.geom, nv.point_geom, 0.000001), nv.point_geom), 2), 
			nv.id, 
			mdgr.target,
			route_id
		from minimumDistanceGeometryOnRoad mdgr
		inner join new_vertices nv on st_equals(mdgr.cp_point_on_road, nv.point_geom)
		returning geom, source, target
	)	
	select 
		id as vertex_id,
		point_geom as cp_point_on_road
	from new_vertices ;

END; $$ 
Language plpgsql;

create or replace function findShortestPath(
	sourceId bigint,
	targetId bigint,
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
			 COALESCE(st_length(geom), 0) as cost,
			 COALESCE(st_length(geom), 0) as reverse_cost
		  FROM roads_tlp;',
		  sourceId,
		  targetId, false) as pd
		  join roads_tlp r
		  on pd.edge = r.id;
END; $$ 
Language plpgsql;

create or replace function revise_gps_geom(
		input_route_id varchar(64)
) Returns table ( 
		geom geometry
) AS $$
DECLARE
	SRID integer := 5179; --SRID: 5179
	SRID_4326 integer := 4326;
	LIMITS integer := 1;
begin
	update gps_history gh 
		set geom_4326 = ST_SetSRID(st_makepoint(gh.lng, gh.lat), 4326) 
	where gh.route_id = input_route_id;

	update gps_history gh
		set geom = st_transform(gh.geom_4326, 5179)
	where gh.route_id = input_route_id;

	-- create nearest road geometry table by gps history
	insert into nearest_neighberhood_road_geom_public select 
		input_route_id,
		gh.idx::integer as idx,
		frst.vertex_id::bigint as vertex_id,
		frst.cp_point_on_road as cp_point_on_road
	from gps_history gh,
		LATERAL findMinDistanceGeometryObjectsByAPoint(
				ST_transform(gh.geom, 5179),
				input_route_id
		) as frst
		where gh.route_id = input_route_id;
	
	-- drop table if exists shortest_path_public;
	insert into shortest_path_public select 
		prev.idx,
		fsp.seq,
		prev.vertex_id as source,
		next.vertex_id as target,
		fsp.node,
		fsp.cost,
		fsp.agg_cost,
		fsp.geom,
		prev.route_id
	from nearest_neighberhood_road_geom_public prev
		inner join nearest_neighberhood_road_geom_public next
			on prev.idx + 1 = next.idx,
		lateral findshortestpath(prev.vertex_id, next.vertex_id, prev.idx) as fsp
		where prev.route_id = input_route_id;
		
	delete from nearest_neighberhood_road_geom_public where route_id = input_route_id;
	delete from roads_tlp_vertices_pgr where route_id = input_route_id;
	delete from roads_tlp where route_id = input_route_id;
	
	return query 
	with revised_gps as (
		select 
			st_transform((ST_DumpPoints(collected_sp.geom)).geom, 4326) as geom
		from (
				select 
					st_lineMerge(st_collect(sp.geom)) as geom 
				from (
					select * 
					from shortest_path_public 
					where route_id = input_route_id 
					order by idx
				) sp 
			) collected_sp
	), reset_shortest_path_table as (
		delete from shortest_path_public where route_id = input_route_id
	)
	select * from revised_gps;

END; $$ 
Language plpgsql;


create or replace function revise_gps(
		input_route_id varchar(64)
) Returns table ( 
		lat float,
		lng float
) AS $$
begin
	return query 
	select
		st_y(geom) as lat,
		st_x(geom) as lng
	from revise_gps_geom(input_route_id);
END; $$ 
Language plpgsql;


select * from revise_gps('-XM0b6vsSYqPMK8hF29CAA');







