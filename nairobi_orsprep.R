library(tidyverse)
library(lubridate)

## Read in Nairobi daily road speeds df
nairobi_df <- readRDS("data/year_df.rds")

## Data processing function to get df into proper format for ors
ors_df <- function(df) {
  df <- df  |>  
    mutate(quarter = 1,
           speed_kph_p50 = speed_kph_mean)  |>   
    rename(hour_of_day = hour) |> 
    select(c("year", "quarter", "hour_of_day", "osm_way_id", 
             "osm_start_node_id", "osm_end_node_id", 
             "speed_kph_mean", "speed_kph_stddev", "speed_kph_p50")) |> 
    na.omit()
  return(df)
}


## List of public holidays that will need to be filtered out
pubholiday_list <- c("2019-01-01", "2019-04-19", "2019-04-22", "2019-05-01", "2019-06-01", "2019-06-05", "2019-08-12", "2019-10-10", "2019-10-20", "2019-10-21", "2019-10-27", "2019-12-12", "2019-12-25", "2019-12-26")
pubholiday_list <- as.Date(pubholiday_list)


## Adding columns and filtering Nairobi road speeds df to split it by semester and holiday periods and to filter out weekends and public holidays
nairobi_df <- nairobi_df |> 
  mutate(date = as.Date(paste0(year, "-", month, "-", day)),
         dayofweek = wday(date, label = TRUE),
  week = ifelse(dayofweek == "Sat" | dayofweek == "Sun", 0, 1),
  pubholiday = ifelse(date %in% pubholiday_list, 1, 0)) |> 
  filter(week == 1 & pubholiday == 0) |> 
  mutate(status = case_when(
    (date >= as.Date("2019-01-02") & date <= as.Date("2019-04-05")) ~ "semester",
    (date >  as.Date("2019-04-05") & date <  as.Date("2019-04-29")) ~ "holiday",
    (date >= as.Date("2019-04-29") & date <= as.Date("2019-08-02")) ~ "semester",
    (date >  as.Date("2019-08-02") & date <  as.Date("2019-08-26")) ~ "holiday",
    (date >= as.Date("2019-08-26") & date <= as.Date("2019-10-25")) ~ "semester",
    (date >  as.Date("2019-10-25")) ~ "holiday",
    TRUE ~ "other" 
  ))

## Setting semester and holiday dfs
semester <- nairobi_df |> 
  filter(status == "semester")

holiday <- nairobi_df |> 
  filter(status == "holiday")

## Combine into list for running through function and writing csvs
df_list <- list(
  "semester_ors" = ors_df(semester),
  "holiday_ors" = ors_df(holiday)
)

## For loop to write csvs for the semester and holiday periods
for (name in names(df_list)) {
  write.csv(df_list[[name]], paste0("data/", name, ".csv"), row.names = FALSE)
}