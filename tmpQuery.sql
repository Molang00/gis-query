drop table if exists roads;

create table roads as
SELECT gid as id, 
	geom,
	rep_cn as address
FROM tl_sprd_manage;

create table yeoido as
select * from roads where address like '�뿬�쓽�룄�룞%';

select * from tl_sprd_manage where rep_cn like '�뿬�쓽�룄�룞%';
			
select * from roads;
select st_setSRID(geom, 5179) from yeoido;
select updategeometrysrid('roads_split', 'geom', 5179);
select st_astext(geom) from yeoido;
select * from roads_split;
select * from yeoido where id in (select id from roads_split);


drop table if exists roads_split;
truncate roads_split;
insert into roads_split
select id, (p_geom).path[1] As path, (p_geom).geom from 
(select 
		r.id,
		st_dump(st_split(r.geom, v.geom)) as p_geom
	from roads r 
		left join roads v
			on ST_Crosses(r.geom, v.geom) = true or ST_touches(r.geom, v.geom)) as a;

drop table if exists roads_tlp;
drop table if exists roads_tlp_vertices_pgr;

create table roads_tlp as select * from roads_split;

alter table roads_tlp add column source integer;
alter table roads_tlp add column target integer;
create index road_source_idx on roads_tlp (source);
create index road_target_idx on roads_tlp (target);

select pgr_createTopology('roads_tlp', 0.0001, 'geom', 'id');

-- create gps history table
 drop table if exists gps_history;
 TRUNCATE gps_history;
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
 	


select id, (p_geom).path[1] As path, (p_geom).geom from 
(select 
		r.id,
		st_dump(st_split(r.geom, v.geom)) as p_geom
	from roads r 
		left join roads v
			on ST_Crosses(r.geom, v.geom) = true or ST_touches(r.geom, v.geom)) as a;
			

CREATE TABLE roads_split_v2 (
    id integer,
    path integer,
    geom geometry(Geometry,5179),
    source integer,
    target integer
);

select (p_geom).path[1] as path, st_astext((p_geom).geom) from (select id, st_dump(geom) as p_geom from roads) as foo order by id;
select id, st_astext(geom) from roads order by id;
select st_astext(geom) from roads_split_union;
select (p_geom).path[1] as path, st_astext((p_geom).geom) from (select st_dump(st_geomFromEWKT('GEOMETRYCOLLECTION(multiLINESTRING((0 0, 10 10, 20 0)), multilinestring((10 10, 20 20)))')) as p_geom) as foo;

select (p_geom).path[1] as path, st_astext((p_geom).geom) from (select st_dump(st_union(st_geomFromEWKT('multiLINESTRING((0 0, 10 10, 20 0))'), st_geomFromEWKT('multilinestring((10 10, 20 20))'))) as p_geom) as foo;
select st_astext(geom) from (select st_union(st_geomFromEWKT('multiLINESTRING((0 0, 10 10, 20 0))'), st_geomFromEWKT('multilinestring((10 10, 20 20))')) as geom) as foo;

drop table roads_split_union;
create table roads_split_union as
select 
	(p_geom).path[1] As path, 
	(p_geom).geom 
from (
		select 
			st_dump(ST_Union(geom)) as p_geom
		from roads
	) as foo;
	
select count(*) from roads_split_union group by path;
	

drop table if exists roads_tlp;
drop table if exists roads_tlp_vertices_pgr;

create table roads_tlp as select * from roads_split_union;

alter table roads_tlp add column source integer;
alter table roads_tlp add column target integer;
create index road_source_idx on roads_tlp (source);
create index road_target_idx on roads_tlp (target);

select pgr_createTopology('roads_tlp', 0.0001, 'geom', 'path');



DROP FUNCTION findmindistancegeometryobjectsbyapoint(geometry);
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
	
select * from nearest_neighberhood_road_geom_public;
	

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
	lateral findshortestpath(prev.source, next.source, prev.idx) as fsp;

select * from nearest_neighberhood_road_geom_public nnrgp;
137762 137766
select * from nearest_neighberhood_road_geom_public order by idx, id;
select * from shortest_path_public order by idx, seq;
select * from roads_tlp where id = 5837

select pgr_createTopology('roads_tlp', 0.0001, 'geom', 'id');


select count(*) from roads_tlp_vertices_pgr; --137737
select count(*) from roads_tlp; --180018
delete from roads_tlp_vertices_pgr where id > 137700;
delete from roads_tlp where id is null;
select * from roads_tlp where id is null;
select id, st_astext(geom), source, target from roads_tlp where source > 137732 or target > 137732;
create table tmp_data_view2 as select id, geom, source, target from roads_tlp where target > 137737;
create table tmp_data_view as select id, geom, source, target from roads_tlp where source > 137737;
select id, geom, source, target from roads_tlp where source >= 137753 or target >= 137753;
select * from roads_tlp order by id;
delete from roads_tlp where source >= 137753 or target >= 137753;
drop table tmp_data_view;

insert into roads_tlp_vertices_pgr(the_geom)
select nr.cp_point_on_line as the_geom
from nearest_neighberhood_road_geom_public nr;

insert into roads_tlp_vertices_pgr(the_geom)
select nr.cp_point_on_line as the_geom
from nearest_neighberhood_road_geom_public nr
returning id, st_astext(the_geom);

with new_vertices as (
	insert into roads_tlp_vertices_pgr(the_geom)
	select nr.cp_point_on_line as the_geom
	from nearest_neighberhood_road_geom_public nr
	returning id, the_geom
), new_edge1 as (
	insert into roads_tlp (geom, source, target)
	select st_geometryn(st_split(st_snap(nr.geom, nr.cp_point_on_line, 0.000001), nr.cp_point_on_line), 1), nr.source, nv.id
	from nearest_neighberhood_road_geom_public nr 
	inner join new_vertices nv on st_equals(nr.cp_point_on_line, nv.the_geom)
	returning geom, source, target
)
insert into roads_tlp (geom, source, target)
select st_geometryn(st_split(st_snap(nr.geom, nr.cp_point_on_line, 0.000001), nr.cp_point_on_line), 2), nv.id, nr.target
from nearest_neighberhood_road_geom_public nr
inner join new_vertices nv on st_equals(nr.cp_point_on_line, nv.the_geom)
returning geom, source, target;

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



select st_astext(st_geometryn(st_split(st_snap(nr.geom, nr.cp_point_on_line, 0.000001), nr.cp_point_on_line), 2))
from nearest_neighberhood_road_geom_public nr;
select st_astext(st_geometryn(st_split(nr.geom, nr.cp_point_on_line), 1)), nr.target
from nearest_neighberhood_road_geom_public nr;

SELECT ST_AsText(st_geometryn(ST_Split(mline, pt), 2)) As wktcut
        FROM (SELECT
    ST_GeomFromText('MULTILINESTRING((10 10, 0 0))') As mline,
    ST_Point(5,5) As pt) As foo;


alter table roads_tlp_vertices_pgr alter column id add generated by default as identity;
alter table roads_tlp alter column id add generated by default as identity;
ALTER TABLE roads_tlp ADD CONSTRAINT primary_key_id PRIMARY KEY(id);







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

-- create nearest road geometry table by gps history
insert into nearest_neighberhood_road_geom_public select 
	'test_route',
	gh.idx::integer as idx,
	frst.vertex_id::bigint as vertex_id,
	frst.cp_point_on_road as cp_point_on_road
from gps_history gh,
	LATERAL findMinDistanceGeometryObjectsByAPoint(
			ST_transform(gh.geom, 5179),
			'test_route'
	) as frst
	where gh.route_id = 'test_route';

select * from nearest_neighberhood_road_geom_public;


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
	where prev.route_id = 'test_route';



