# Event System

The new event system is a major change in the codebase. It is a complete rewrite of the event system. But it should be far more resilient and easier to use.

- Integrated Rails Event Store
- Created base classes and interfaces
- Implemented tool-related events as a proof of concept

The system is ready for further enhancement with additional event types and handlers

--

TODO: 
- Make a list of all events we think we will need
- Make a list of all handlers we think we will need
- Figure out side effects of each event
- Figure out which events are blocking
(for instance could a request for human assitance block one task, while others coninue, or should any request for human inntervention block all tasks on a project?)
- test test test test test our desired behavior

--

Now that we have done quite some refactoring is contextable sitll needed? and do we really need ancestry on agent_activities?

by definition ONE agent works on a task and all agent_activities will be connected to that task and we know what order they happened by their time stamp

HOWEVER we do have the concept of tasks spawning subtasks and task dependencies that we need to handle in the coordinator agent better - it seems like tasks definitely have ancestry and also are always blocking to their parent tasks (if their parent task did not need that task done, why would it have spawned it?)

--

Lastly we have to circle back to the front end and refigure out how to display our new architecture. Make sure it is all reactive.