library(sf)
library(tidyverse)
library(lubridate)
library(ggplot2)


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
  select(hour, date, osm_way_id, osm_start_node_id, osm_end_node_id, speed_kph_mean, osmhighway, status)

holiday_roads <- morn_roads |>
  filter(status == "holiday") |>
  group_by(osm_start_node_id, osm_end_node_id, osmhighway) |>
  summarise(speed_kph_mean = mean(speed_kph_mean, na.rm = TRUE))

semester_roads <- morn_roads |>
  filter(status == "semester") |>
  group_by(osm_start_node_id, osm_end_node_id, osmhighway) |>
  summarise(speed_kph_mean = mean(speed_kph_mean, na.rm = TRUE))

semhol_diff <- inner_join(semester_roads, holiday_roads, by = c("osm_start_node_id", "osm_end_node_id")) |>
  mutate(speed_diff = speed_kph_mean.y - speed_kph_mean.x)


semhol_diff <- semhol_diff |> na.omit()
# semhol_diff_filt <- semhol_diff |>
#   filter(osmhighway.x %in% c("primary", "secondary", "tertiary", "residential", "motorway"))
# # filter by osm id and check out binom distr on the high change ones
#
# p1 <- ggplot(semhol_diff_filt, aes(x = speed_diff, fill = osmhighway.x)) +
#   geom_density(aes(y = ..density..), color = NA, alpha = 0.2) +
#   theme_minimal() +
#   labs(x = "Mean Speed (kph)",
#        y = "Density",  # Updated label
#        title = "Distribution of Mean Speed during School v Holiday Mornings") +
#   guides(color = FALSE) +
#   theme(legend.position = "top",
#         legend.key.size = unit(2, "lines"),  # Increase legend key size
#         legend.text = element_text(size = 12)  # Increase legend text size
#   )
#
# p1

morn_cutoff_90 <- quantile(semhol_diff$speed_diff, 0.90)
morn_cutoff_80 <- quantile(semhol_diff$speed_diff, 0.80)

morn_cutoff_10 <- quantile(semhol_diff$speed_diff, 0.10)
morn_cutoff_20 <- quantile(semhol_diff$speed_diff, 0.20)

# Filter rows where 'value' is greater than the cutoff
morn_top_10 <- semhol_diff |>
  filter(speed_diff > morn_cutoff_90)

morn_top_20 <- semhol_diff |>
  filter(speed_diff > morn_cutoff_80)

morn_top10highway <- morn_top_10 |>
  group_by(osmhighway.x) |>
  dplyr::summarise(top10_n = n(), .groups = "drop")

morn_top20highway <- morn_top_20 |>
  group_by(osmhighway.x) |>
  dplyr::summarise(top20_n = n(), .groups = "drop")

## Bottom
morn_bot_10 <- semhol_diff |>
  filter(speed_diff < morn_cutoff_10)

morn_bot_20 <- semhol_diff |>
  filter(speed_diff < morn_cutoff_20)

morn_bot10highway <- morn_bot_10 |>
  group_by(osmhighway.x) |>
  dplyr::summarise(bot10_n = n(), .groups = "drop")

morn_bot20highway <- morn_bot_20 |>
  group_by(osmhighway.x) |>
  dplyr::summarise(bot20_n = n(), .groups = "drop")



binom_test_func <- function(k, n, p) {
  if(k == 0){
    return(1)
  } else {
    p_val <- binom.test(x = k, n = n, p = p, alternative = "two.sided")$p.value
    return(p_val)
  }
}


morn_roadcounts <- semhol_diff  |>
  group_by(osmhighway.x) |>
  dplyr::summarise(n = n(), .groups = "drop")


morn_roadcounts <- morn_roadcounts |>
  left_join(morn_top10highway, by = "osmhighway.x") |>
  left_join(morn_top20highway, by = "osmhighway.x") |>
  left_join(morn_bot10highway, by = "osmhighway.x") |>
  left_join(morn_bot20highway, by = "osmhighway.x") |>
  mutate(expected_n10 = n * 0.1,
         expected_n20 = n * 0.2,
         percent_top10 = top10_n / n,
         percent_top20 = top20_n / n,
         p10 = expected_n10 / n,
         p20 = expected_n20 / n,
         percent_bot10 = bot10_n / n,
         percent_bot20 = bot20_n / n) |>
  mutate_all(~replace_na(., 0))

morn_roadcounts <- morn_roadcounts  |>
  mutate(
    binom_test_pval_top10 = mapply(binom_test_func, top10_n, n, p10),
    binom_test_pval_top20 = mapply(binom_test_func, top20_n, n, p20),
    binom_test_pval_bot10 = mapply(binom_test_func, bot10_n, n, p10),
    binom_test_pval_bot20 = mapply(binom_test_func, bot20_n, n, p20),
    rep_top10_morn = if_else(binom_test_pval_top10 < 0.05,
                             if_else(top10_n < expected_n10, "underrepresented", "overrepresented"), ""),
    rep_top20_morn = if_else(binom_test_pval_top20 < 0.05,
                             if_else(top20_n < expected_n20, "underrepresented", "overrepresented"), ""),
    rep_bot10_morn = if_else(binom_test_pval_bot10 < 0.05,
                             if_else(bot10_n < expected_n10, "underrepresented", "overrepresented"), ""),
    rep_bot20_morn = if_else(binom_test_pval_bot20 < 0.05,
                             if_else(bot20_n < expected_n20, "underrepresented", "overrepresented"), ""))

morn_binoms <- morn_roadcounts |>
  select(osmhighway.x, rep_top10_morn, rep_top20_morn, rep_bot10_morn, rep_bot20_morn)


