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


select * from findShortestPath(9882, 5952);