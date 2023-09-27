library(httr)
library(sf)
library(tidyverse)
library(furrr)

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

    POST(url = url, body = body, add_headers(headers))
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

get_route <- function(origin, dest, arrival) {
    get_ors_response(
        origin_coords = origin |> st_coordinates() |> as.numeric(),
        dest_coords = dest |> st_coordinates() |> as.numeric(),
        arrival = arrival
    ) |>
        parse_ors_response()
}

# Call `future::plan(multisession, workers = {n_workers})` before `get_routes`
# for parallel processing of routes
get_routes <- function(
        origins,
        origin_ids,
        destinations = origins, 
        dest_ids = origin_ids, 
        arrivals,
        ...
) {
    stopifnot(
        length(origins) == length(origin_ids),
        length(destinations) == length(dest_ids),
        is(origins, "sfc_POINT"),
        is(destinations, "sfc_POINT")
    )

    grid <- expand.grid(
        origin = origins, 
        dest = destinations, 
        arrival = arrivals
    )
    ids <- expand.grid(
        origin_id = origin_ids,
        dest_id = dest_ids,
        requested_arrival = arrivals
    )
    
    grid |>
        future_pmap(get_route) |>
        reduce(bind_rows) |>
        bind_cols(ids)
}
