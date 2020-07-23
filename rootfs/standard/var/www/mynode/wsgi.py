from mynode import app, stop_app, on_shutdown, ServiceExit

if __name__ == "__main__":
    try:
        app.run(host='0.0.0.0', port=8000)
    except ServiceExit:
        # Stop background threads
        stop_app()

    print("Service www exiting...")