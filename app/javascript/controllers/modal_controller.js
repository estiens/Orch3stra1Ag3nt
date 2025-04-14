import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]
  
  connect() {
    // Initialize modal when controller connects
    this.setupKeyboardEvents()
  }
  
  disconnect() {
    // Clean up when controller disconnects
    this.removeKeyboardEvents()
  }
  
  open(event) {
    if (event.currentTarget.dataset.modalUrl) {
      const url = event.currentTarget.dataset.modalUrl
      this.fetchModal(url)
    } else {
      this.showModal()
    }
  }
  
  fetchModal(url) {
    fetch(url, {
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
    .then(response => response.text())
    .then(html => {
      Turbo.renderStreamMessage(html)
      this.showModal()
    })
  }
  
  showModal() {
    document.body.classList.add("modal-open")
    this.element.classList.add("active")
  }
  
  close() {
    document.body.classList.remove("modal-open")
    this.element.classList.remove("active")
    this.element.innerHTML = ""
  }
  
  closeBackground(event) {
    if (event.target === this.element) {
      this.close()
    }
  }
  
  setupKeyboardEvents() {
    this.boundKeyHandler = this.handleKeyboard.bind(this)
    document.addEventListener("keydown", this.boundKeyHandler)
  }
  
  removeKeyboardEvents() {
    document.removeEventListener("keydown", this.boundKeyHandler)
  }
  
  handleKeyboard(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }
}
