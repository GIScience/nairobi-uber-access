install.packages("foreach")
install.packages("doParallel")
library(foreach)
library(doParallel)

# Set up parallel backend
num_cores <- detectCores() - 4
cl <- makeCluster(num_cores)
registerDoParallel(cl)

tic.clear()
# loop through hexgrid
result <- data.frame(bbox=NA, geometry=NA, way_points=NA, legs=NA, departure=NA, arrival=NA, geom=NA, status=NA, id_origin=NA, id_destination=NA, distance=NA,duration=NA)

tic("first 15")
#for (i in 1:15) {
result <- foreach(outer_index = 1:15, .combine = rbind.fill) %dopar% {
  #tic(glue("run {i} / {nrow(hex_grid)}"))
  library(sf)
  library(httr)
  library(dplyr)
  library(purrr)
  library(plyr)


  origin <- hex_grid[outer_index, ]

  resp_df <- data.frame(bbox=NA, geometry=NA, way_points=NA, legs=NA, departure=NA, arrival=NA, geom=NA, status=NA, id_origin=NA, id_destination=NA, distance=NA,duration=NA)

  for (inner_index in 1:nrow(hex_grid)) {
    if (outer_index != inner_index) {
      destination <- hex_grid[inner_index, ]

      headers = c('Content-Type' = 'application/json')

      or_coord <- origin$centroid |> st_coordinates() |> as.numeric()
      dest_coord <-
        destination$centroid |> st_coordinates() |> as.numeric()

      body <- list(
        coordinates = list(c(or_coord[1], or_coord[2]),
                           c(dest_coord[1], dest_coord[2])),
        arrival = "2018-02-23T06:00:00",
        instructions = F
      ) |> jsonlite::toJSON(auto_unbox = T)

      res <-
        VERB("POST",
             url = "http://localhost:8080/ors/v2/directions/driving-car",
             body = body,
             add_headers(headers))

      if (res$status_code != 200) {
        df_resp <- data.frame(status = res$status_code)
        df_resp$id_origin <- outer_index
        df_resp$id_destination <- inner_index
        resp_df <- rbind.fill(resp_df, df_resp)


      } else {
        json_resp <- res$content |> rawToChar() |> jsonlite::fromJSON()
        df_resp <- json_resp$routes |> as.data.frame()


        df_resp <- df_resp |> mutate(geom = gp2sf(geometry)) |>
          st_sf(crs = "EPSG:4326")



        df_resp$id_origin <- outer_index
        df_resp$id_destination <- inner_index
        df_resp$status <- res$status_code
        df_resp$distance <- df_resp$summary$distance
        df_resp$duration <- df_resp$summary$duration
        df_resp <- df_resp |> select(-c(summary))
        result |>  names()
        df_resp |>  names()
        resp_df <- rbind.fill(resp_df,
                             df_resp |> select(bbox, geometry, way_points, legs, departure, arrival, geom, status, id_origin, id_destination, distance, duration))

      }

    }


  }
  resp_df

}
toc()
nrow(result)
