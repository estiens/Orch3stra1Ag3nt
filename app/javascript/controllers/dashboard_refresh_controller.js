import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: Number,
    url: String
  }
  
  static targets = ["indicator"]
  
  connect() {
    this.startRefreshing()
    this.setupProjectStateListeners()
  }
  
  disconnect() {
    this.stopRefreshing()
    this.removeProjectStateListeners()
  }
  
  startRefreshing() {
    this.refreshTimer = setInterval(() => {
      this.refresh()
    }, this.intervalValue || 5000) // Default to 5 seconds if not specified
  }
  
  stopRefreshing() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }
  
  setupProjectStateListeners() {
    // Listen for project pause/resume events
    document.addEventListener('project:paused', this.handleProjectStateChange.bind(this))
    document.addEventListener('project:resumed', this.handleProjectStateChange.bind(this))
    document.addEventListener('task:paused', this.handleProjectStateChange.bind(this))
    document.addEventListener('task:resumed', this.handleProjectStateChange.bind(this))
    document.addEventListener('human_intervention:created', this.handleProjectStateChange.bind(this))
    document.addEventListener('human_intervention:resolved', this.handleProjectStateChange.bind(this))
    document.addEventListener('human_input_request:created', this.handleProjectStateChange.bind(this))
    document.addEventListener('human_input_request:answered', this.handleProjectStateChange.bind(this))
  }
  
  removeProjectStateListeners() {
    document.removeEventListener('project:paused', this.handleProjectStateChange.bind(this))
    document.removeEventListener('project:resumed', this.handleProjectStateChange.bind(this))
    document.removeEventListener('task:paused', this.handleProjectStateChange.bind(this))
    document.removeEventListener('task:resumed', this.handleProjectStateChange.bind(this))
    document.removeEventListener('human_intervention:created', this.handleProjectStateChange.bind(this))
    document.removeEventListener('human_intervention:resolved', this.handleProjectStateChange.bind(this))
    document.removeEventListener('human_input_request:created', this.handleProjectStateChange.bind(this))
    document.removeEventListener('human_input_request:answered', this.handleProjectStateChange.bind(this))
  }
  
  handleProjectStateChange(event) {
    console.log(`Dashboard refreshing due to ${event.type}`)
    // Immediately refresh the dashboard when project/task state changes
    this.refresh()
  }
  
  refresh() {
    // Show refresh indicator if it exists
    if (this.hasIndicatorTarget) {
      this.indicatorTarget.classList.remove('hidden')
    }
    
    fetch(this.urlValue, {
      headers: {
        Accept: "text/vnd.turbo-stream.html"
      }
    })
    .then(response => response.text())
    .then(html => {
      Turbo.renderStreamMessage(html)
      // Hide refresh indicator
      if (this.hasIndicatorTarget) {
        this.indicatorTarget.classList.add('hidden')
      }
    })
    .catch(error => {
      console.error("Dashboard refresh error:", error)
      // Hide refresh indicator even on error
      if (this.hasIndicatorTarget) {
        this.indicatorTarget.classList.add('hidden')
      }
    })
  }
  
  // Manual refresh button handler
  manualRefresh(event) {
    event.preventDefault()
    this.refresh()
  }
}
