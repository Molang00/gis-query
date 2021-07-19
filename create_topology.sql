drop table if exists roads;

create table roads as
SELECT gid as id, 
	geom,
	rep_cn as address
FROM tl_sprd_manage;

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
