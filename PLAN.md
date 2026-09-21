# Browser drive

THe perpose is to create an environment where an agent can write EYG code that explores the DOM.

## Create a phantom.js driver

The single inserted script should act as a plugin that shows a chat box.That chat box can be dragged around or expand to full hight on the left or right.
Assume there is an LLM connect but for the demo mock responses.
The agent only has one tool which is to Run EYG code.
The eyg interpreter is used and has the following effects
- GetElements(query_string)
- WriteCSS(text)
- InsertButton(text)

When the agent runs the script is show collapsed but all the effects that run are listed below.
Show a little check mark as each effect checks off. if a script has lots of effects then the list of running effects should collapse
A user can expand the list of effects and/or expand the code.

## The demo

1. visit di.se 
  - show the user asking for the graph to be made bigger. show the result
  - Show the asking for a visual effect when they hover over the graph
  - Show them asking for a new button
2. Create a cool demo to add a new feature to sj.se
  - Use your imagination
  - expand the available effects if need be. only add at most another 2

For the demo's show the script injection process, then record a video of the user working on the page and chatting to the agent to make the changes to the page.

## The tutorial

Write a guide that explains

- [ ] How to run the interpreter in JavaScript
  - [ ] How can we make this easier
- [ ] How to set up an agent loop in JS that uses only the EYG tool
- [ ] How to pass a context to the agent. The agent needs the EYG syntax guide as part of it's system prompt.
  - [ ] Make sure there is a full system prompt that explains to the agent how to work well
- [ ] Review the guide that it is concise, explains EYG well and explains that you can write anything outside the harness and the agent is securly sandboxed only able to use the explicitly defined effects.