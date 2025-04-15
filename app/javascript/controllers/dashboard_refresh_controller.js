import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: Number,
    url: String
  }
  
  static targets = ["indicator"]
  
  connect() {
    this.startRefreshing()
  }
  
  disconnect() {
    this.stopRefreshing()
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
