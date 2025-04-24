import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: Number,
    url: String
  }
  
  static targets = ["indicator"]
  
  connect() {
    this.setupProjectStateListeners()
  }
  
  disconnect() {
    this.removeProjectStateListeners()
  }
  
  setupProjectStateListeners() {
    // Listen for project pause/resume events
    document.addEventListener('project:paused', this.handleProjectStateChange.bind(this))
    document.addEventListener('project:resumed', this.handleProjectStateChange.bind(this))
  }
  
  removeProjectStateListeners() {
    document.removeEventListener('project:paused', this.handleProjectStateChange.bind(this))
    document.removeEventListener('project:resumed', this.handleProjectStateChange.bind(this))
  }
  
  handleProjectStateChange(event) {
    console.log(`Projects list refreshing due to ${event.type}`)
    // Immediately refresh the projects list when project state changes
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
      console.error("Projects refresh error:", error)
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