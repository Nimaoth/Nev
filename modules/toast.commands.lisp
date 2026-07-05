(
  (context toast)

  (inject self ToastService "getServiceChecked(ToastService)")

  (command showToast [(title string) (message string) (color string)] () "")
)