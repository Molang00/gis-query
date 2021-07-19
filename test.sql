DROP FUNCTION findMinDistanceGeometryObjectsByAPoint(double precision,double precision);
create or replace function findMinDistanceGeometryObjectsByAPoint(
	lat float, 
	lng float
) Returns table (st_distance float, db_id numeric(10,0), geom geometry) AS $$
DECLARE
	SRID integer := 4326; --SRID: WGS84
	METER_SRID integer := 26986; --Massachusetts state plane meters
	Point geometry := null;
BEGIN
	Point = ST_SetSRID(ST_MakePoint(lng, lat), SRID); 
	
	return query	
	select ST_DISTANCE(
		ST_Transform(dw.wkb_geometry, METER_SRID), 
		ST_Transform(POINT, METER_SRID)
	) as st_distance, 
	dw.db_id as db_id,
	dw.wkb_geometry as geom,
	ST_Project(Point, geom)
	from dw_rd_link_sample_wgs84 dw 
	order by wkb_geometry <-> Point
	limit 10;
END; $$ 
Language plpgsql;

-- select * from findMinDistanceGeometryObjectsByAPoint(37.530334, 126.922615);

with recursive MinDistanceGeometryObjects as(
	select 1 as idx, * from findMinDistanceGeometryObjectsByAPoint(37.530334, 126.922615)
	union
	select 2 as idx, * from findMinDistanceGeometryObjectsByAPoint(37.529533, 126.923058)
	union
	select 3 as idx, * from findMinDistanceGeometryObjectsByAPoint(37.528864, 126.922367)
) select 
	mdgo.idx as prev_idx,
	mdgo_next.idx as next_idx,
	mdgo.db_id as prev_id,
	mdgo_next.db_id as next_id,
	ST_DISTANCE(
		ST_Transform(mdgo.geom, 26986),
		ST_Transform(mdgo_next.geom, 26986)
	) as connected,
	mdgo.st_distance + mdgo_next.st_distance as aways
from MinDistanceGeometryObjects mdgo
inner join MinDistanceGeometryObjects mdgo_next
	on mdgo.idx = mdgo_next.idx - 1
where 
	ST_DISTANCE(
		ST_Transform(mdgo.geom, 26986),
		ST_Transform(mdgo_next.geom, 26986)
	) = 0
order by mdgo.st_distance + mdgo_next.st_distance;
