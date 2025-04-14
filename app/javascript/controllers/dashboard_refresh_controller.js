import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: Number,
    url: String
  }
  
  connect() {
    this.startRefreshing()
  }
  
  disconnect() {
    this.stopRefreshing()
  }
  
  startRefreshing() {
    this.refreshTimer = setInterval(() => {
      this.refresh()
    }, this.intervalValue)
  }
  
  stopRefreshing() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }
  
  refresh() {
    fetch(this.urlValue, {
      headers: {
        Accept: "text/vnd.turbo-stream.html"
      }
    })
    .then(response => response.text())
    .then(html => {
      Turbo.renderStreamMessage(html)
    })
  }
}
