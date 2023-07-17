import {Controller} from "@hotwired/stimulus"

// Connects to data-controller="photo"
export default class extends Controller {

    loadImage() {
        console.log("Hello")
        const [file] = photo_image.files
        if (file) {
            blah_2.src = URL.createObjectURL(file)
            document.getElementById("blah_1").classList.add('d-none')
            document.getElementById(("blah_2")).classList.remove('d-none')
            document.getElementById(("blah_3")).classList.remove('d-none')
        }
    }

    changeImage() {
        document.getElementById("blah_1").classList.remove('d-none')
        document.getElementById(("blah_2")).classList.add('d-none')
        document.getElementById(("blah_3")).classList.add('d-none')
    }

    clickUpload() {
        document.getElementById('photo_image').click()
    }
}