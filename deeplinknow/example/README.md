# deeplinknow_example

The first-launch flow with `deeplinknow`: initialize, ask for the deferred deep link once, and route to its path with a plain `Navigator`.

```sh
flutter run --dart-define=DLN_API_KEY=dln_pub_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Use your app's public key from the DeepLinkNow dashboard. Links under `/products/<id>` open the product screen; any other path opens a generic screen that lists the query parameters. The home screen shows the outcome (or `lastError`) and has buttons to check again with `force: true` and to reset the first-launch state.
