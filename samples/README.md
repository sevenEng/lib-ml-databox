### Synopsis
This is an example of driver/app developed using `lib-ml-databox`.
The driver and app together implements a square root solver using Newton's methond.

+ The app shows a web interface which accepts user's input:
a real number whose square root to solve,
and the stop condition of the iterative computation.
+ The driver observes a datasource where commands from app comes from,
the commands could be either `start, <number>` or `stop, <number>`.
When started, the driver keeps iterating to find the answer, until the app tells it to stop.
+ After app starts a computation, it observes on a results datasource, where the driver
keeps writing to with result from each iteration.
App controls when to stop based on the user provied stop condition.
At the same time, results from the datasource are showed on the web UI by the app.

### Install
Please refer to `README` file of [Databox](https://github.com/me-box/databox) repostiory,
the section [Developing apps and drivers without the SDK](https://github.com/me-box/databox#developing-apps-and-drivers-without-the-sdk) is of particular help for this.
