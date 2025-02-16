



curl -X PUT --location "https://matrix.hoohoot.org/_matrix/client/r0/rooms/!CdhmJpkYAURXzzYGGg:hoohoot.org/send/m.room.message/fa882911-484d-4a93-b609-aab7c13f6aba" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $MATRIX_BEARER_TOKEN" \
    -d '{
          "msgtype": "m.text",
          "body": "This is a text description and an image.",
          "format": "org.matrix.custom.html",
          "formatted_body": "<h1>Movie Downloaded</h1><p>The Wild Robot (2024) [WEBDL-1080p] https://www.imdb.com/title/tt29623480/<br>Requested by : Michel<br>Description: Earum quos libero placeat consequuntur. Necessitatibus assumenda molestiae et iure ipsum officia quia quo. Aut consectetur doloribus accusantium perferendis optio autem esse. Ratione omnis assumenda reiciendis a. Molestias laudantium sit odit excepturi aspernatur dolorum aliquid consectetur. Et aut sunt excepturi nam pariatur.…</p>"
        }'
