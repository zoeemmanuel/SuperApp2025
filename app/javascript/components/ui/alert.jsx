import * as React from "react"

const Alert = React.forwardRef(({ className, variant = "default", children, ...props }, ref) => (
  <div
    ref={ref}
    role="alert"
    className={`p-4 rounded-md border ${variant === "destructive" ? "bg-red-50 border-red-200 text-red-700" : "bg-white"} ${className}`}
    {...props}
  >
    {children}
  </div>
))
Alert.displayName = "Alert"

const AlertTitle = React.forwardRef(({ className, ...props }, ref) => (
  <h5
    ref={ref}
    className={`mb-1 font-medium leading-none ${className}`}
    {...props}
  />
))
AlertTitle.displayName = "AlertTitle"

export { Alert, AlertTitle }
