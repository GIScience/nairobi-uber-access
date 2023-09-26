library(httr)
library(sf)
library(tidyverse)

get_ors_response <- function(
        origin_coords, 
        dest_coords, 
        arrival, 
        url = "http://localhost:8080/ors/v2/directions/driving-car"
) {
    headers = c('Content-Type' = 'application/json')
    
    body <- list(
        coordinates = list(origin_coords, dest_coords),
        arrival = arrival,
        instructions = FALSE
    ) |> jsonlite::toJSON(auto_unbox = TRUE)

    res <- POST(url = url, body = body, add_headers(headers))
}

parse_ors_response <- function(res) {
    if (res$status_code != 200) {
        result <- data.frame(status = res$status_code)
    } else {
        json_resp <- res$content |> rawToChar() |> jsonlite::fromJSON()
        result <- json_resp$routes |> 
            as.data.frame() |> 
            mutate(
                geom = gp2sf(geometry),
                status = res$status_code
            ) |>
            st_sf(crs = "EPSG:4326") |>
            unnest(summary)
    }
    result
}

get_route <- function(origin_coord, dest_coord, arrival) {
    get_ors_response(
        origin_coords = origin_coord |> st_coordinates() |> as.numeric(),
        dest_coords = dest_coord |> st_coordinates() |> as.numeric(),
        arrival = arrival
    ) |>
        parse_ors_response()
}

get_routes <- function(
        origin_centroids, 
        dest_centroids, 
        origin_ids, 
        dest_ids, 
        arrivals
) {
    stopifnot(
        length(origin_centroids) == length(origin_ids),
        length(dest_centroids) == length(dest_ids)
    )

    grid <- expand.grid(
        origin_coord = origin_centroids, 
        dest_coord = dest_centroids, 
        arrival = arrivals
    )
    ids <- expand.grid(
        origin_id = origin_ids, 
        dest_id = dest_ids, 
        requested_arrival = arrivals
    )
    
    grid |>
        pmap(get_route) |>
        reduce(bind_rows) |>
        bind_cols(ids)
}
