library(sf)
library(tidyverse)
library(lubridate)
library(cluster)


#### Clustering

## Read in files
morn <- readRDS("data/morn_nairobi.rds")
nairobi_roads <- st_read("data/nairobi_2019.geojson")
st_crs(nairobi_roads) <- 4326


## Add osm highway tags tot he roads
morn_roads <- morn |>
  left_join(nairobi_roads, by = c("osm_start_node_id" = "osmstartnodeid", "osm_end_node_id" = "osmendnodeid"))

## Subset columns
morn_roads <- morn_roads |>
  select(hour, date, osm_way_id, osm_start_node_id, osm_end_node_id, speed_kph_mean, osmhighway)

## Retrieve road type means and sds
highway_means <- morn_roads |>
  group_by(osmhighway) |>
  summarise(mean_speed_kph = mean(speed_kph_mean, na.rm = TRUE),
            sd_speed_kph = sd(speed_kph_mean, na.rm = TRUE), .groups = "drop")

## Group_by and summarise mean speeds for the roads by date
morn_roads <- morn_roads %>%
  group_by(osm_way_id, osm_start_node_id, osm_end_node_id, osmhighway, date) %>%
  summarise(speed_kph_mean = mean(speed_kph_mean, na.rm = TRUE), .groups = "drop")

## Pivot road segments wider to add cols for each time period
morn_roads_wide <- morn_roads |>
  pivot_wider(names_from = "date",
              values_from = speed_kph_mean,
              values_fill = NA)

## Join cols for highway means and sds
morn_roads_wide <- morn_roads_wide |>
  left_join(highway_means, by = "osmhighway")

## Re-scale and re-center speeds
morn_roads_wide_normalized <- morn_roads_wide %>%
  rowwise() %>%
  mutate(across(starts_with("2019-"), ~(.x - mean_speed_kph) / sd_speed_kph))

## Replace NAs with normalized mean for each road segment
morn_roads_wide_normalized <- morn_roads_wide_normalized %>%
  rowwise() %>%
  mutate(mean = mean(c_across(starts_with("2019-")), na.rm = TRUE)) %>%
  mutate(across(starts_with("2019-"),
                ~ifelse(is.na(.), mean, .)))

## Select speed cols for clustering
data_to_cluster <- morn_roads_wide_normalized %>%
  select(starts_with("2019-"))

## Clustering
dist_matrix <- dist(data_to_cluster, method = "euclidean")
hclust_result <- hclust(dist_matrix, method = "complete")

## Dendrogram
plot(hclust_result, main = "Hierarchical Clustering Dendrogram", ylab = "Distance")


## Anova and Clustering Loop
for (i in seq(from = 2, to = 10, by = 1)) {
  clusters <- cutree(hclust_result, k = i)
  morn_roads_wide_normalized$cluster <- clusters
  anova_result <- aov(mean ~ as.factor(cluster), data = morn_roads_wide_normalized)
  print(paste("k =", i))
  print(table(clusters))
  print(summary(anova_result))
}


## Assign cluster
cluster_assignments <- cutree(hclust_result, k = 2)
morn_roads_wide$cluster <- cluster_assignments

#saveRDS(morn_roads_wide, "data/morn_roads_wide.rds")

## Map roads with clusters

morn_roads_clu <- morn_roads_wide |>  left_join(nairobi_roads[c(1,3,6)], by = c("osm_start_node_id" = "osmstartnodeid", "osm_end_node_id" = "osmendnodeid"))
morn_roads_clu <- st_as_sf(morn_roads_clu)
mapview::mapview(morn_roads_clu, zcol = "cluster")
