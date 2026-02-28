    def enter_distros(self):
        if self.load_distros_catalog(back_state="menu", refresh=False):
            self.state = "distros"
            self.distros_stage = "distros"
            self.status("Distro catalog loaded from cache", "ok")

