DROP FUNCTION if exists findbestshortestpath();
create or replace function findBestShortestPath()
returns shortest_path[] as $$ 
declare
	LOOP_SIZE integer := 0;
begin
	LOOP_SIZE = (select idx from gps_history order by idx desc limit 1)::integer;
	for i in 0..LOOP_SIZE loop
		raise notice 'Iterator: %', i;
		union select * from shortest_path where idx = i;
	end loop;
	
	return rst
end;
$$ language plpgsql;

select * from findBestShortestPath();