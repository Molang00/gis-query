drop table if exists edge_table;
create or replace function h_bigint(text) returns bigint as $$
 select ('x'||substr(md5($1),1,16))::bit(64)::bigint;
$$ language sql;

create table edge_table as
	select 
		h_bigint(concat(dw.db_id,'_',dw_next.db_id)) as id,
		dw.db_id as source,
		dw_next.db_id as target,
		(dw.length + dw_next. as cost
	from dw_rd_link_sample_wgs84 dw
	inner join dw_rd_link_sample_wgs84 dw_next 
		on (dw.db_id != dw_next.db_id) and ((dw.wkb_geometry <-> dw_next.wkb_geometry) = 0)
	order by dw_next.db_id;