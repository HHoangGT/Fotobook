import {Controller} from "@hotwired/stimulus"

// Connects to data-controller="album"
export default class extends Controller {

    connect() {
        this.listFile = []
        this.fileInput = document.getElementById('album_images');
    }

    clickUpload() {
        document.getElementById('album_images').click()
    }

    loadImages() {
        function fileListFrom(files) {
            const b = new ClipboardEvent("").clipboardData || new DataTransfer()
            for (const file of files) b.items.add(file)
            return b.files
        }

        const images = document.getElementById('images');
        const totalImages = document.getElementById('total-images');
        totalImages.innerText = this.fileInput.files.length;
        images.innerHTML = '';
        if (this.fileInput.files.length > 0) {
            for (const imageFile of this.fileInput.files) {
                this.listFile.push(imageFile)
                const reader = new FileReader();
                reader.addEventListener('load', function (e) {
                    images.innerHTML += `
                        <div class="rounded border-dark border-2 bg-light position-relative render-images
                                    col-12 col-md-3 d-flex align-items-center justify-content-center px-0 mb-3">
                            <img src="${reader.result}" class="img-fluid" id = "${imageFile.name}">
                            <div style="width: 30px; height: 30px" id="blah_3" data-action="click->album#deleteImage"
                                data-album-file-name-param = "${imageFile.name}">
                                <img
                                src="/assets/cancel-668f12b638081df3280dd4042dceddca41ba3e21b731072c26e9102aa8a5303e.png" 
                                style="position: absolute; top: 5px; right: 5px; width: 20px; height: 20px">
                            </div>
                        </div>
                    `;
                });
                reader.readAsDataURL(imageFile);
            }
        } else {
            images.innerHTML = '';
        }
        this.fileInput.files = fileListFrom(this.listFile)
        // console.log(this.fileInput.files)
    }

    deleteImage(e) {
        function fileListFrom(files) {
            const b = new ClipboardEvent("").clipboardData || new DataTransfer()
            for (const file of files) b.items.add(file)
            return b.files
        }

        const fileDeleted = e.params['fileName']
        let list = []
        for (const file of this.listFile) {
            if (file.name === fileDeleted) continue
            list.push(file)
        }
        document.getElementById(`${fileDeleted}`).parentNode.remove()
        this.listFile = list
        this.fileInput.files = fileListFrom(this.listFile)
        document.getElementById('total-images').innerText = this.fileInput.files.length;
        console.log(this.fileInput.files)
    }
}
