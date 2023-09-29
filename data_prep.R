library(sf)
library(tidyverse)
library(lubridate)


## Read in files
year_df <- readRDS("data/year_df.rds")
nairobi_roads <- st_read("data/nairobi_2019.geojson")
st_crs(nairobi_roads) <- 4326

## Subset Nairobi daily road speeds to morning rush hour
morn <- year_df |> 
  mutate(date = as.Date(paste0(year, "-", month, "-", day))) |> 
  filter(hour %in% c(6,7,8))

## Designate future filtering for public holidays
pubholiday_list <- c("2019-01-01", "2019-04-19", "2019-04-22", "2019-05-01", "2019-06-01", "2019-06-05", "2019-08-12", "2019-10-10", "2019-10-20", "2019-10-21", "2019-10-27", "2019-12-12", "2019-12-25", "2019-12-26")
pubholiday_list <- as.Date(pubholiday_list)


## Group road speeds by date and add columns for semester and holiday as well as week day type and public holiday
########### Fix mid-semester breaks
morn_df <- morn |> 
  group_by(date) |>
  mutate(dayofweek = wday(date, label = TRUE),
         week = ifelse(dayofweek == "Sat" | dayofweek == "Sun", 0, 1),
         holiday = ifelse(date %in% pubholiday_list, 1, 0),
         status = case_when(
           (date >= as.Date("2019-01-02") & date <= as.Date("2019-04-05")) ~ "semester1",
           (date >  as.Date("2019-04-05") & date <  as.Date("2019-04-29")) ~ "holiday1",
           (date >= as.Date("2019-04-29") & date <= as.Date("2019-08-02")) ~ "semester2",
           (date >  as.Date("2019-08-02") & date <  as.Date("2019-08-26")) ~ "holiday2",
           (date >= as.Date("2019-08-26") & date <= as.Date("2019-10-25")) ~ "semester3",
           (date >  as.Date("2019-10-25")) ~ "holiday3",
           TRUE ~ "other"))

saveRDS(morn_df, "data/morn_df.rds")

## Preparation of weekday only morn df for plotting time series and extracting extreme high and low congestion days

week_df <- morn_df |> filter(week == 1 & holiday == 0) |> 
  group_by(date) |> 
  summarise(mean_speed_kph = mean(speed_kph_mean, na.rm = TRUE))

top10_days <- week_df |> 
  slice_max(order_by = mean_speed_kph, n = 10) 

bottom10_days <- week_df |> 
  slice_min(order_by = mean_speed_kph, n = 10)

extreme20_days <- rbind(top10_days, bottom10_days)

# Write csv so that it can be shared externally as opposed to RDS
write_csv(extreme20_days, "data/extreme20_daysNairobi.csv")

## Preparation of individual semester and holiday periods
summarize_period <- function(df, period_label) {
  
  # Filter df based on the period_label, week, and holiday status
  summarized_data <- df |>
    filter(status == period_label, week == 1, holiday == 0) |>
    ungroup() |> 
    summarise(mean_kph = mean(speed_kph_mean, na.rm = TRUE),
              se_kph = sd(speed_kph_mean, na.rm = TRUE) / sqrt(n()),
              min_date = min(date),
              max_date = max(date))
  
  return(summarized_data)
}

df_list <- list(
  sem1 = summarize_period(morn_df, "semester1"),
  sem2 = summarize_period(morn_df, "semester2"),
  sem3 = summarize_period(morn_df, "semester3"),
  hol1 = summarize_period(morn_df, "holiday1"),
  hol2 = summarize_period(morn_df, "holiday2"),
  hol3 = summarize_period(morn_df, "holiday3")
)

# Convert the list to environment variables
list2env(df_list, envir = .GlobalEnv)

# Save all the data frames in the list into a single RData file
save(list = names(df_list), file = "data/semhol_dfs.RData")


## Prepartion of morning roads df (combines Nairobi roads and osm highway types with speeds)
morn_roads <- morn |> 
  left_join(nairobi_roads, by = c("osm_start_node_id" = "osmstartnodeid", "osm_end_node_id" = "osmendnodeid")) |> 
  group_by(date, osmhighway) |> 
  dplyr::summarise(mean_speed_kph = mean(speed_kph_mean, na.rm = TRUE), .groups = "drop") |>
  mutate(dayofweek = wday(date, label = TRUE),
         week = ifelse(dayofweek == "Sat" | dayofweek == "Sun", 0, 1),
         holiday = ifelse(date %in% pubholiday_list, 1, 0)) |> 
  filter(osmhighway %in% c("motorway", "primary", "secondary", "tertiary", "trunk", "residential"))

saveRDS(morn_roads, "data/morn_roads.rds")

## Preparation of semester holiday speed difference gpkg
## Setting both dfs
semester <- morn_df |> 
  filter(status == "semester1" | status == "semester2" | status == "semester3") |> 
  group_by(osm_start_node_id, osm_end_node_id, osm_way_id) |> 
  summarise(mean_speed_kph = mean(speed_kph_mean, na.rm = TRUE)) |> 
  ungroup()

holiday <- morn_df |> 
  filter(status == "holiday1" | status == "holiday2" |status == "holiday3") |> 
  group_by(osm_start_node_id, osm_end_node_id, osm_way_id) |> 
  summarise(mean_speed_kph = mean(speed_kph_mean, na.rm = TRUE)) |> 
  ungroup()

## Setting joining fields and inner join to only include roads in both time periods
join_fields <- c("osm_start_node_id", "osm_end_node_id", 
                 "osm_way_id")

semhol_diff <- semester |> 
  inner_join(holiday, by = join_fields) |> 
  mutate(mean_speed_diff = mean_speed_kph.x - mean_speed_kph.y)

## Join on Nairobi roads for mapping
semhol_diff <- inner_join(semhol_diff, nairobi_roads, by = c("osm_way_id" = "osmwayid", "osm_start_node_id" = "osmstartnodeid", "osm_end_node_id" = "osmendnodeid")) |> 
  st_as_sf()

st_write(semhol_diff, "data/semhol_diff.gpkg")


