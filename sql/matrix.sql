--- Find large rooms
SELECT r.name, s.room_id, s.current_state_events
FROM room_stats_current s
       LEFT JOIN room_stats_state r USING (room_id)
ORDER BY current_state_events DESC
LIMIT 20;

SELECT rss.name, s.room_id, COUNT(s.room_id)
FROM state_groups_state s
       LEFT JOIN room_stats_state rss USING (room_id)
GROUP BY s.room_id, rss.name
ORDER BY COUNT(s.room_id) DESC
LIMIT 20;
