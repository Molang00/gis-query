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