module Main exposing (..)

import Html exposing (Html, text)


type alias Model = { }

emptyModel : Model
emptyModel = { }

main : Program (Maybe Model) Model Msg
main =
    Html.programWithFlags
        { init = init
        , view = view
        , update = update
        , subscriptions = \_ -> Sub.none
        }

init : Maybe Model -> ( Model, Cmd Msg )
init model =
    Maybe.withDefault emptyModel model ! []

type Msg = NoOp

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            model ! []

view : Model -> Html Msg
view model =
    Html.text "Hello World!"

